pragma solidity ^0.8.14;

import {IFncyToken} from "./interfaces/IFncyToken.sol";
import {IFncyTokenAirdrop} from "./interfaces/IFncyTokenAirdrop.sol";
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

contract FncyTokenAirdrop is IFncyTokenAirdrop, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    constructor() {
        _disableInitializers();
    }

    /*
    ########################
    ###      Modifier    ###
    ########################
    */
    modifier onlyExecutor() {
        _validateAirdropExecutor(_msgSender());
        _;
    }

    /*
    ########################
    ###      Storage     ###
    ########################
    */
    IFncyToken private _fncyToken;
    uint256 private _totalAirdropAmount;
    mapping(address => bool) private _isExecutor;
    address[] private _executors;

    function initialize(address fncyToken, address initExecutor) public initializer {
        __Ownable_init();
        if (fncyToken == address(0)) revert InvalidParameter();

        address sender = _msgSender();

        if (initExecutor == address(0)) {
            initExecutor = sender;
        } else if (initExecutor != sender) {
            addAirdropExecutor(sender);
        }

        addAirdropExecutor(initExecutor);

        _fncyToken = IFncyToken(fncyToken);
        emit ChangeTargetToken(address(0), fncyToken);
    }

    // @inheritdoc IFncyTokenAirdrop
    function airdrop(address to, uint256 amount) external nonReentrant onlyExecutor {
        _totalAirdropAmount += amount;
        _send(to, amount);
    }

    // @inheritdoc IFncyTokenAirdrop
    function getTotalAirdropAmount() external view override returns(uint256) {
        return _totalAirdropAmount;
    }

    // @inheritdoc IFncyTokenAirdrop
    function isExecutor(address executor) external view returns(bool) {
        return _isExecutor[executor];
    }

    // @inheritdoc IFncyTokenAirdrop
    function getExecutors() external view returns(address[] memory) {
        return _executors;
    }

    // @inheritdoc IFncyTokenAirdrop
    function addAirdropExecutor(address executor) public override onlyOwner {
        if (executor == address(0)) revert InvalidParameter();
        if (_isExecutor[executor]) revert AlreadyAirdropExecutePerm(executor);

        _isExecutor[executor] = true;
        _executors.push(executor);

        emit AddAirdropExecutor(executor);
    }

    // @inheritdoc IFncyTokenAirdrop
    function removeAirdropExecutor(address executor) external override onlyOwner {
        if (executor == address(0)) revert InvalidParameter();
        if (!_isExecutor[executor]) revert NotExistsAirdropExecutor(executor);

        int256 indexOf = -1;
        for (uint256 i = 0; i < _executors.length; i++) {
            if (_executors[i] != executor) continue;
            indexOf = int256(i);
            break;
        }

        if (indexOf >= 0) {
            // 배열 순서 재조정
            if (_executors.length > 1 && uint256(indexOf) != _executors.length - 1) {
                _executors[uint256(indexOf)] = _executors[_executors.length - 1];
            }
            _executors.pop();
            _isExecutor[executor] = false;

            emit RemoveAirdropExecutor(executor);
        }
    }

    function _validateAirdropExecutor(address executor) internal view returns(bool) {
        if (!_isExecutor[executor]) revert UnauthorizedAirdropExecute(executor);
        return true;
    }

    function _send(address to, uint256 amount) internal returns(bool){
        if(to == address(0)) revert InvalidParameter();
        if(amount == 0) revert InvalidParameter();
        if(address(_fncyToken) == address(0)) revert TokenNotSet();

        return _fncyToken.transfer(to, amount);
    }
}