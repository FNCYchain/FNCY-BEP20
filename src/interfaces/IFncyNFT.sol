// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {IERC721Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC721/IERC721Upgradeable.sol";

interface IFncyNFT is IERC721Upgradeable {
    /*
    ########################
    ###      Events      ###
    ########################
    */
    event AddMinter(address indexed minter);
    event RemoveMinter(address indexed minter);
    event Mint(address indexed to, uint256 indexed tokenId, string tokenURI);
    event BatchMint(address indexed to, uint256[] tokenIds, string[] tokenURIs);
    event Burn(uint256 indexed tokenId);
    event BatchBurn(uint256[] tokenIds);
    event SetBaseURI(string baseURI);
    event SetTokenURI(uint256 indexed tokenId, string tokenURI);
    event Lock(uint256 indexed tokenId, address indexed locker);
    event Unlock(uint256 indexed tokenId, address indexed unlocker);
    event RoyaltyUpdated(address indexed receiver, uint96 feeNumerator);

    /*
    ########################
    ###      Errors      ###
    ########################
    */
    error InvalidParameter();
    error UnauthorizedMinting(address caller);
    error AlreadyMinterAddress();
    error NotExistsMinterAddress();
    error MaxSupplyExceeded(uint256 requestAmount, uint256 availableAmount);
    error TokenNotExists(uint256 tokenId);
    error TokenLocked(uint256 tokenId);
    error TokenNotLocked(uint256 tokenId);
    error UnauthorizedTokenOperation(address caller, uint256 tokenId);
    error BatchSizeMismatch();
    error BatchSizeTooLarge(uint256 size, uint256 maxSize);

    /*
    ########################
    ###    Functions     ###
    ########################
    */

    /**
     * @dev Minter 주소 목록 반환
     * @return minters Minter 주소 배열
     */
    function getMinters() external view returns(address[] memory minters);

    /**
     * @dev 총 소각된 NFT 수량 반환
     * @return totalBurned 총 소각 수량
     */
    function getTotalBurned() external view returns(uint256 totalBurned);

    /**
     * @dev Minter 권한 확인
     * @param minter 확인할 주소
     * @return isMinter Minter 권한 유무
     */
    function isMinter(address minter) external view returns(bool isMinter);

    /**
     * @dev Minter 권한 추가 (onlyOwner)
     * @param minter 추가할 Minter 주소
     */
    function addMinter(address minter) external;

    /**
     * @dev Minter 권한 제거 (onlyOwner)
     * @param minter 제거할 Minter 주소
     */
    function removeMinter(address minter) external;

    /**
     * @dev NFT 개별 발행 (onlyMinter)
     * @param to 발행 받을 주소
     * @param tokenId 토큰 ID
     * @param _tokenURI 토큰 메타데이터 URI
     */
    function mint(address to, uint256 tokenId, string calldata _tokenURI) external;

    /**
     * @dev NFT 배치 발행 (onlyMinter)
     * @param to 발행 받을 주소
     * @param tokenIds 토큰 ID 배열
     * @param tokenURIs 토큰 메타데이터 URI 배열
     */
    function batchMint(address to, uint256[] calldata tokenIds, string[] calldata tokenURIs) external;

    /**
     * @dev NFT 개별 소각 (onlyMinter)
     * @param tokenId 소각할 토큰 ID
     */
    function burn(uint256 tokenId) external;

    /**
     * @dev NFT 배치 소각 (onlyMinter)
     * @param tokenIds 소각할 토큰 ID 배열
     */
    function batchBurn(uint256[] calldata tokenIds) external;

    /**
     * @dev 베이스 URI 설정 (onlyOwner)
     * @param baseURI 새로운 베이스 URI
     */
    function setBaseURI(string calldata baseURI) external;

    /**
     * @dev 개별 토큰 URI 설정 (onlyOwner)
     * @param tokenId 토큰 ID
     * @param _tokenURI 새로운 토큰 URI
     */
    function setTokenURI(uint256 tokenId, string calldata _tokenURI) external;

    /**
     * @dev 최대 발행 가능한 NFT 수량 반환
     * @return maxSupply 최대 발행량
     */
    function getMaxSupply() external view returns(uint256 maxSupply);
}