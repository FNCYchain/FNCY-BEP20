//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {IFncyToken} from "./interfaces/IFncyToken.sol";
import {ERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {EIP712Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol";

// @dev BSC Chain 에서 사용될 FNCY Chain FNCY Coin 과 1:1 비율을 갖는 BSC FNCY Token Contract
contract FncyToken is IFncyToken, ERC20Upgradeable, OwnableUpgradeable, EIP712Upgradeable {
    constructor() {
        _disableInitializers();
    }
    /*
    ########################
    ###      Constant    ###
    ########################
    */
    // @dev FNCY Chain 의 최대 발행량
    uint256 public constant MAX_SUPPLY = 2_000_000_000 ether;
    // @dev FNCY Chain 의 최종 민팅 블록 번호
    uint256 public constant STOP_MINTING_BLOCK = 201_785_712;
    // @dev dEaD Address
    address private constant DEAD_ADDRESS = address(0x000000000000000000000000000000000000dEaD);

    /*
    ########################
    ###      Modifier    ###
    ########################
    */
    modifier onlyMinter() {
        _validateMinter(msg.sender);
        _;
    }

    /*
    ########################
    ###      Storage     ###
    ########################
    */
    mapping(address => bool) private _isMinter;
    address[] private _minters;
    uint256 private circulating;
    uint256 private totalBurned;
    uint256 public fncyEndSnapshot;
    uint256 public deployBlock;

    function initialize(uint256 _fncyEndSnapshot) public initializer {
        if (_fncyEndSnapshot == 0) revert InvalidParameter();
        fncyEndSnapshot = _fncyEndSnapshot;
        deployBlock = block.number;

        __Ownable_init();
        __ERC20_init("FNCY", "FNCY");
        __EIP712_init("FNCY", "0.0.1");

        _isMinter[msg.sender] = true;
        _minters.push(msg.sender);
    }

    // @inheritdoc IFncyToken
    function getMinters() public view override returns(address[] memory) {
        return _minters;
    }

    // @inheritdoc IFncyToken
    function getTotalBurned() external view override returns(uint256) {
        return totalBurned;
    }

    // @inheritdoc IFncyToken
    function getCirculating() external view override returns(uint256) {
        return circulating;
    }

    // @inheritdoc IFncyToken
    function isMinter(address minter) override public view returns(bool) {
        return _isMinter[minter];
    }

    // @inheritdoc IFncyToken
    function addMinter(address minter) override external onlyOwner {
        if (minter == address(0)) revert InvalidParameter();
        if (_isMinter[minter]) revert AlreadyMinterAddress();

        _minters.push(minter);
        _isMinter[minter] = true;

        emit AddMinter(minter);
    }

    // @inheritdoc IFncyToken
    function removeMinter(address minter) override external onlyOwner {
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

    // @inheritdoc IFncyToken
    function mint(address account, uint256 amount) external override onlyMinter {
        if (amount == 0 || account == address(0)) revert InvalidParameter();

        uint256 _totalSupply = totalSupply();
        if (_totalSupply + amount > MAX_SUPPLY) revert MaxSupplyExceeded(amount, MAX_SUPPLY - _totalSupply);

        // 실제 유통량
        circulating += amount;

        _mint(account, amount);
        emit Mint(account, amount);
    }

    // @inheritdoc IFncyToken
    function burn(address account, uint256 amount) external override onlyMinter {
        if (amount == 0) revert InvalidParameter();
        if (circulating < amount) revert InsufficientCirculating(circulating, amount);

        circulating -= amount;
        totalBurned += amount;

        _burn(account, amount);
        emit Burn(account, amount);
    }

    // @inheritdoc IFncyToken
    function lock(uint256 amount) external override {
        if (amount == 0) revert InvalidParameter();
        uint256 balance = balanceOf(_msgSender());
        if (balance < amount) revert InsufficientBalance(balance, amount);
        if (circulating < amount) revert InsufficientCirculating(circulating, amount);

        circulating -= amount;

        _transfer(_msgSender(), address(this), amount);
        emit Lock(_msgSender(), address(this), amount);
    }

    // @inheritdoc IFncyToken
    function softBurnWithAdmin(uint256 amount) external override onlyOwner {
        if (amount == 0) revert InvalidParameter();
        uint256 balance = balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance(balance, amount);
        if (circulating < amount) revert InsufficientCirculating(circulating, amount);

        circulating -= amount;
        totalBurned += amount;

        _transfer(address(this), DEAD_ADDRESS, amount);
        emit SoftBurn(address(this), DEAD_ADDRESS, amount);
    }

    // @inheritdoc IFncyToken
    function isMintingAllowed() public view returns (bool) {
        uint256 remainBlock = STOP_MINTING_BLOCK - fncyEndSnapshot;

        return block.number <= deployBlock + remainBlock;
    }

    // @inheritdoc IFncyToken
    function remainingMintableSupply() public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply >= MAX_SUPPLY) return 0;
        return MAX_SUPPLY - _totalSupply;
    }

    // @inheritdoc IFncyToken
    function rescueTokens(uint256 amount) external onlyOwner {
        if (amount == 0) revert InvalidParameter();

        uint256 balance = balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance(balance, amount);

        // Lock 시점에 Circulating 을 감소시켰으므로 Circulating 값 증가
        circulating += amount;

        _transfer(address(this), _msgSender(), amount);
        emit RescueTokens(_msgSender(), amount);
    }

    function _validateMinter(address minter) internal view returns (bool) {
        if (!_isMinter[minter]) revert UnauthorizedMinting(minter);
        return true;
    }
}