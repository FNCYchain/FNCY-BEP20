pragma solidity ^0.8.14;

import {IFncyToken} from "./interfaces/IFncyToken.sol";
import {IFncyTokenAirdrop} from "./interfaces/IFncyTokenAirdrop.sol";
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";

contract FncyTokenAirdrop is IFncyTokenAirdrop, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    constructor() {
        _disableInitializers();
    }
    /*
    ########################
    ###      Constant    ###
    ########################
    */
    uint256 public constant MAX_BATCH_SIZE = 100; // 최대 배치 크기

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
    uint256 private _airdropLimit;
    uint256 private _totalAirdropAmount;
    uint256 private _totalAirdropCount;
    uint256 private _uniqueRecipientCount;

    mapping(address => bool) private _isExecutor;
    address[] private _executors;

    mapping(address => uint256) private _receivedAmount;
    mapping(address => bool) private _hasReceived;

    function initialize(address fncyToken, address initExecutor) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        if (fncyToken == address(0)) revert InvalidParameter();

        address sender = _msgSender();
        address executorToAdd = initExecutor == address(0) ? sender : initExecutor;

        if (executorToAdd != sender) {
            _isExecutor[sender] = true;
            _executors.push(sender);
            emit AddAirdropExecutor(sender);
        }

        // 초기 executor 추가
        _isExecutor[executorToAdd] = true;
        _executors.push(executorToAdd);
        emit AddAirdropExecutor(executorToAdd);

        // 토큰 설정
        _fncyToken = IFncyToken(fncyToken);
        emit ChangeTargetToken(address(0), fncyToken);

        // 에어드랍 제한 없음으로 초기화
        _airdropLimit = type(uint256).max;
    }

    // @inheritdoc IFncyTokenAirdrop
    function airdrop(address from, address to, uint256 amount) external override nonReentrant onlyExecutor {
        _checkAirdropLimit(amount);

        uint256 allowance = _fncyToken.allowance(from, address(this));
        if (allowance < amount) revert InsufficientAllowance(allowance, amount);

        _totalAirdropAmount += amount;
        _receivedAmount[to] += amount;

        _totalAirdropCount++;
        if (!_hasReceived[to]) {
            _hasReceived[to] = true;
            _uniqueRecipientCount++;
        }


        bool success = _fncyToken.transferFrom(from, to, amount);
        require(success, "Airdrop transfer failed");

        emit TokenAirdropped(to, amount);
    }

    function batchAirdrop(address[] calldata froms, address[] calldata recipients, uint256[] calldata amounts) external override nonReentrant onlyExecutor {
        if (recipients.length == 0) revert InvalidParameter();
        if (recipients.length != amounts.length) revert InvalidParameter();
        if (recipients.length > MAX_BATCH_SIZE) revert BatchSizeTooLarge(recipients.length, MAX_BATCH_SIZE);

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert InvalidParameter();
            if (amounts[i] == 0) revert InvalidParameter();
            totalAmount += amounts[i];
        }

        _checkAirdropLimit(totalAmount);
        _totalAirdropAmount += totalAmount;

        for (uint256 i = 0; i < recipients.length; i++) {

            _receivedAmount[recipients[i]] += amounts[i];

            _totalAirdropCount++;
            if (!_hasReceived[recipients[i]]) {
                _hasReceived[recipients[i]] = true;
                _uniqueRecipientCount++;
            }

            bool success = _fncyToken.transferFrom(froms[i],recipients[i], amounts[i]);
            require(success, "Batch airdrop transfer failed");
            emit TokenAirdropped(recipients[i], amounts[i]);
        }
    }

    // @inheritdoc IFncyTokenAirdrop
    function airdropFromPool(address to, uint256 amount) external override nonReentrant onlyExecutor {
        _checkAirdropLimit(amount);
        uint256 contractBalance = _fncyToken.balanceOf(address(this));
        if (contractBalance < amount) revert InsufficientContractBalance(contractBalance, amount);

        _totalAirdropAmount += amount;
        _receivedAmount[to] += amount;

        _totalAirdropCount++;
        if (!_hasReceived[to]) {
            _hasReceived[to] = true;
            _uniqueRecipientCount++;
        }

        bool success = _send(to, amount);
        require(success, "Pool airdrop transfer failed");

        emit TokenAirdropped(to, amount);
    }

    // @inheritdoc IFncyTokenAirdrop
    function batchAirdropFromPool(address[] calldata recipients, uint256[] calldata amounts) external override nonReentrant onlyExecutor {
        if (recipients.length == 0) revert InvalidParameter();
        if (recipients.length != amounts.length) revert InvalidParameter();
        if (recipients.length > MAX_BATCH_SIZE) revert BatchSizeTooLarge(recipients.length, MAX_BATCH_SIZE);

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert InvalidParameter();
            if (amounts[i] == 0) revert InvalidParameter();
            totalAmount += amounts[i];
        }

        _checkAirdropLimit(totalAmount);

        // 컨트랙트의 토큰 잔액 확인
        uint256 contractBalance = _fncyToken.balanceOf(address(this));
        if (contractBalance < totalAmount) revert InsufficientContractBalance(contractBalance, totalAmount);

        _totalAirdropAmount += totalAmount;

        for (uint256 i = 0; i < recipients.length; i++) {
            _receivedAmount[recipients[i]] += amounts[i];

            _totalAirdropCount++;
            if (!_hasReceived[recipients[i]]) {
                _hasReceived[recipients[i]] = true;
                _uniqueRecipientCount++;
            }

            bool success = _send(recipients[i], amounts[i]);
            require(success, "Pool batch airdrop transfer failed");
            emit TokenAirdropped(recipients[i], amounts[i]);
        }
    }

    // @inheritdoc IFncyTokenAirdrop
    function setAirdropLimit(uint256 limit) external override onlyOwner {
        uint256 oldLimit = _airdropLimit;
        _airdropLimit = limit;

        emit AirdropLimitChanged(oldLimit, limit);
    }

    // @inheritdoc IFncyTokenAirdrop
    function changeTargetToken(address newToken) external onlyOwner {
        if (newToken == address(0)) revert InvalidParameter();
        address oldToken = address(_fncyToken);

        _fncyToken = IFncyToken(newToken);

        emit ChangeTargetToken(oldToken, newToken);
    }

    function getAirdropStatus() external view override returns(uint256 totalExecuted, uint256 totalRecipients, uint256 totalAmount) {
        return (_totalAirdropCount, _uniqueRecipientCount, _totalAirdropAmount);
    }

    // @inheritdoc IFncyTokenAirdrop
    function getTotalAirdropAmount() external view override returns(uint256) {
        return _totalAirdropAmount;
    }

    // @inheritdoc IFncyTokenAirdrop
    function getAirdropLimit() external view override returns(uint256) {
        return _airdropLimit;
    }

    // @inheritdoc IFncyTokenAirdrop
    function getRemainingAirdropAmount() external view override returns(uint256) {
        if (_totalAirdropAmount >= _airdropLimit) {
            return 0;
        }
        return _airdropLimit - _totalAirdropAmount;
    }

    // @inheritdoc IFncyTokenAirdrop
    function getReceivedAmount(address recipient) external view override returns(uint256) {
        return _receivedAmount[recipient];
    }

    // @inheritdoc IFncyTokenAirdrop
    function isExecutor(address executor) external view override returns(bool) {
        return _isExecutor[executor];
    }

    // @inheritdoc IFncyTokenAirdrop
    function getExecutors() external view override returns(address[] memory) {
        return _executors;
    }

    // @inheritdoc IFncyTokenAirdrop
    function getContractTokenBalance() external view override returns(uint256) {
        return _fncyToken.balanceOf(address(this));
    }

    // @inheritdoc IFncyTokenAirdrop
    function depositToPool(uint256 amount) external override onlyOwner {
        if (amount == 0) revert InvalidParameter();

        // transferFrom 전에 allowance 확인
        uint256 allowance = _fncyToken.allowance(_msgSender(), address(this));
        if (allowance < amount) revert InsufficientAllowance(allowance, amount);

        bool success = _fncyToken.transferFrom(_msgSender(), address(this), amount);
        require(success, "Pool deposit failed");

        emit PoolDeposited(_msgSender(), amount);
    }

    // @inheritdoc IFncyTokenAirdrop
    function withdrawFromPool(uint256 amount) external override onlyOwner {
        if (amount == 0) revert InvalidParameter();

        uint256 contractBalance = _fncyToken.balanceOf(address(this));
        if (contractBalance < amount) revert InsufficientContractBalance(contractBalance, amount);

        bool success = _fncyToken.transfer(_msgSender(), amount);
        require(success, "Pool withdrawal failed");

        emit PoolWithdrawn(_msgSender(), amount);
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

        uint256 length = _executors.length;
        uint256 indexOf = 0;
        bool found = false;

        for (uint256 i = 0; i < length; i++) {
            if (_executors[i] == executor) {
                indexOf = i;
                found = true;
                break;
            }
        }

        if (found) {
            if (indexOf != length - 1) {
                _executors[indexOf] = _executors[length - 1];
            }

            _executors.pop();
            _isExecutor[executor] = false;

            emit RemoveAirdropExecutor(executor);
        }
    }

    /**
     * @dev 에어드랍 실행 권한 검증
     * @param executor 검증할 주소
     * @return 권한 유무
     */
    function _validateAirdropExecutor(address executor) internal view returns(bool) {
        if (!_isExecutor[executor]) revert UnauthorizedAirdropExecute(executor);
        return true;
    }

    /**
     * @dev 토큰 전송 함수
     * @param to 수신자
     * @param amount 수량
     * @return 성공 여부
     */
    function _send(address to, uint256 amount) internal returns(bool) {
        if(to == address(0)) revert InvalidParameter();
        if(amount == 0) revert InvalidParameter();
        if(address(_fncyToken) == address(0)) revert TokenNotSet();

        return _fncyToken.transfer(to, amount);
    }

    /**
     * @dev 에어드랍 제한량 체크
     * @param amount 체크할 양
     */
    function _checkAirdropLimit(uint256 amount) internal view {
        if (_totalAirdropAmount + amount > _airdropLimit) {
            revert MaxAirdropLimitExceeded();
        }
    }
}
