//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {IFncyNFT} from "./interfaces/IFncyNFT.sol";
import {ERC721Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {EIP712Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol";
import {IERC165Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/IERC165Upgradeable.sol";

// @dev BSC Chain에서 사용될 FNCY Chain NFT와 연동되는 BSC FNCY NFT Contract
contract FncyNFT is IFncyNFT, ERC721Upgradeable, ERC721URIStorageUpgradeable, OwnableUpgradeable, EIP712Upgradeable {
    constructor() {
        _disableInitializers();
    }

    /*
    ########################
    ###      Constant    ###
    ########################
    */
    // @dev NFT 최대 발행량
    uint256 public constant MAX_SUPPLY = 1_000_000_000_000;
    // @dev 배치 처리 최대 크기
    uint256 public constant MAX_BATCH_SIZE = 500;

    /*
    ########################
    ###      Modifier    ###
    ########################
    */
    modifier onlyMinter() {
        _validateMinter(msg.sender);
        _;
    }

    modifier tokenExists(uint256 tokenId) {
        if (!_exists(tokenId)) revert TokenNotExists(tokenId);
        _;
    }

    /*
    ########################
    ###      Storage     ###
    ########################
    */
    mapping(address => bool) private _isMinter;
    address[] private _minters;

    uint256 private _currentTokenId;
    uint256 private _totalBurned;
    string private _baseTokenURI;

    function initialize(string memory name, string memory symbol, string memory baseURI) public initializer {
        __Ownable_init();
        __ERC721_init(name, symbol);
        __ERC721URIStorage_init();
        __EIP712_init("FNCY NFT", "1.0.0");

        _baseTokenURI = baseURI;
        _currentTokenId = 1; // 토큰 ID는 1부터 시작

        // 초기 배포자를 Minter로 설정
        _isMinter[msg.sender] = true;
        _minters.push(msg.sender);
    }

    // @inheritdoc IFncyNFT
    function getMinters() public view override returns(address[] memory) {
        return _minters;
    }

    // @inheritdoc IFncyNFT
    function getTotalBurned() external view override returns(uint256) {
        return _totalBurned;
    }

    // @inheritdoc IFncyNFT
    function isMinter(address minter) public view override returns(bool) {
        return _isMinter[minter];
    }

    // @inheritdoc IFncyNFT
    function addMinter(address minter) external override onlyOwner {
        if (minter == address(0)) revert InvalidParameter();
        if (_isMinter[minter]) revert AlreadyMinterAddress();

        _minters.push(minter);
        _isMinter[minter] = true;

        emit AddMinter(minter);
    }

    // @inheritdoc IFncyNFT
    function removeMinter(address minter) external override onlyOwner {
        if (minter == address(0)) revert InvalidParameter();
        if (!_isMinter[minter]) revert NotExistsMinterAddress();

        uint256 length = _minters.length;
        uint256 indexOf = 0;
        bool found = false;

        for (uint256 i = 0; i < length; i++) {
            if (_minters[i] == minter) {
                indexOf = i;
                found = true;
                break;
            }
        }

        if (found) {
            if (indexOf != length - 1) {
                _minters[indexOf] = _minters[length - 1];
            }

            _minters.pop();
            _isMinter[minter] = false;

            emit RemoveMinter(minter);
        }
    }

    // @inheritdoc IFncyNFT
    function mint(address to, uint256 tokenId, string calldata _tokenURI) external override onlyMinter {
        if (to == address(0) || tokenId == 0) revert InvalidParameter();
        if (_currentTokenId > MAX_SUPPLY) revert MaxSupplyExceeded(1, MAX_SUPPLY - (_currentTokenId - 1));

        // State changes before external call (CEI pattern)
        if (tokenId >= _currentTokenId) {
            _currentTokenId = tokenId + 1;
        }

        // External calls
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, _tokenURI);

        emit Mint(to, tokenId, _tokenURI);
    }

    // @inheritdoc IFncyNFT
    function batchMint(address to, uint256[] calldata tokenIds, string[] calldata tokenURIs) external override onlyMinter {
        if (to == address(0)) revert InvalidParameter();
        if (tokenIds.length == 0 || tokenIds.length != tokenURIs.length) revert BatchSizeMismatch();
        if (tokenIds.length > MAX_BATCH_SIZE) revert BatchSizeTooLarge(tokenIds.length, MAX_BATCH_SIZE);

        uint256 remaining = MAX_SUPPLY - (_currentTokenId - 1);
        if (tokenIds.length > remaining) revert MaxSupplyExceeded(tokenIds.length, remaining);

        // State changes before external calls (CEI pattern)
        uint256 maxTokenId = _currentTokenId - 1;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (tokenIds[i] == 0) revert InvalidParameter();
            if (tokenIds[i] > maxTokenId) {
                maxTokenId = tokenIds[i];
            }
        }
        _currentTokenId = maxTokenId + 1;

        // External calls
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _safeMint(to, tokenIds[i]);
            _setTokenURI(tokenIds[i], tokenURIs[i]);
        }

        emit BatchMint(to, tokenIds, tokenURIs);
    }

    // @inheritdoc IFncyNFT
    function burn(uint256 tokenId) external override onlyMinter tokenExists(tokenId) {
        _totalBurned++;
        _burn(tokenId);

        emit Burn(tokenId);
    }

    // @inheritdoc IFncyNFT
    function batchBurn(uint256[] calldata tokenIds) external override onlyMinter {
        if (tokenIds.length == 0) revert InvalidParameter();
        if (tokenIds.length > MAX_BATCH_SIZE) revert BatchSizeTooLarge(tokenIds.length, MAX_BATCH_SIZE);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (!_exists(tokenIds[i])) revert TokenNotExists(tokenIds[i]);

            _totalBurned++;
            _burn(tokenIds[i]);
        }

        emit BatchBurn(tokenIds);
    }

    // @inheritdoc IFncyNFT
    function setBaseURI(string calldata baseURI) external override onlyOwner {
        _baseTokenURI = baseURI;
        emit SetBaseURI(baseURI);
    }

    // @inheritdoc IFncyNFT
    function setTokenURI(uint256 tokenId, string calldata _tokenURI) external override onlyOwner tokenExists(tokenId) {
        _setTokenURI(tokenId, _tokenURI);
        emit SetTokenURI(tokenId, _tokenURI);
    }

    // @inheritdoc IFncyNFT
    function getMaxSupply() external pure override returns(uint256) {
        return MAX_SUPPLY;
    }
    /**
     * @dev 베이스 URI 반환
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @dev 토큰 URI 반환 (베이스 URI + 개별 URI 조합)
     */
    function tokenURI(uint256 tokenId) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    /**
     * @dev 전송 전 잠금 상태 확인
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @dev 소각 처리
     */
    function _burn(uint256 tokenId) internal override(ERC721Upgradeable, ERC721URIStorageUpgradeable) {
        super._burn(tokenId);
    }

    /**
     * @dev Minter 권한 검증
     */
    function _validateMinter(address minter) internal view returns (bool) {
        if (!_isMinter[minter]) revert UnauthorizedMinting(minter);
        return true;
    }

    function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC721Upgradeable, ERC721URIStorageUpgradeable, IERC165Upgradeable)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}