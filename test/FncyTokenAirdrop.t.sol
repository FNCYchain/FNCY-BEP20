// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {FncyToken} from "../src/FncyToken.sol";
import {FncyTokenAirdrop} from "../src/FncyTokenAirdrop.sol";
import {IFncyToken} from "../src/interfaces/IFncyToken.sol";
import {IFncyTokenAirdrop} from "../src/interfaces/IFncyTokenAirdrop.sol";
import {Test, console} from "forge-std/Test.sol";

contract FncyTokenAirdropTest is Test {
    // Token Contract
    FncyToken                   public fncyToken;
    FncyToken                   public _tokenImplementation;
    ProxyAdmin                  public tokenProxyAdmin;
    TransparentUpgradeableProxy public tokenProxy;

    // Airdrop Contract
    FncyTokenAirdrop            public airdropContract;
    FncyTokenAirdrop            public _airdropImplementation;
    ProxyAdmin                  public airdropProxyAdmin;
    TransparentUpgradeableProxy public airdropProxy;

    address public _developer   = address(1); // 개발자, 초기 배포자
    address public _foundation  = address(2); // 재단
    address public _minter      = address(3); // 민팅용 주소
    address public _executor    = address(4); // 에어드랍 실행자
    address public _user1       = address(5); // 일반 사용자 1
    address public _user2       = address(6); // 일반 사용자 2
    address public _user3       = address(7); // 일반 사용자 3

    uint256 public MAX_SUPPLY = 2_000_000_000 ether;
    uint256 public MAX_BATCH_SIZE = 100;

    function setUp() public {
        vm.startPrank(_developer);

        // ==========================================
        // 1. 토큰 컨트랙트 배포 및 설정
        // ==========================================

        // Proxy Admin 배포
        tokenProxyAdmin = new ProxyAdmin();

        // 토큰 컨트랙트 배포 (프록시 구현체)
        _tokenImplementation = new FncyToken();

        // Proxy 배포 (Transparent)
        bytes memory tokenInitializeData = abi.encodeWithSignature("initialize(uint256)", 23_000_000);
        tokenProxy = new TransparentUpgradeableProxy(
            address(_tokenImplementation),
            address(tokenProxyAdmin),
            tokenInitializeData
        );

        // Proxy Admin Owner 변경
        tokenProxyAdmin.transferOwnership(_foundation);

        fncyToken = FncyToken(address(tokenProxy));

        // 재단에게 20억개 민팅
        fncyToken.mint(_foundation, MAX_SUPPLY);

        // 토큰 Owner 변경
        fncyToken.transferOwnership(_foundation);

        // ==========================================
        // 2. 에어드랍 컨트랙트 배포 및 설정
        // ==========================================

        // Airdrop Proxy Admin 배포
        airdropProxyAdmin = new ProxyAdmin();

        // 에어드랍 컨트랙트 배포 (프록시 구현체)
        _airdropImplementation = new FncyTokenAirdrop();

        // Airdrop Proxy 배포 (Transparent)
        bytes memory airdropInitializeData = abi.encodeWithSignature(
            "initialize(address,address)",
            address(fncyToken),
            _executor
        );
        airdropProxy = new TransparentUpgradeableProxy(
            address(_airdropImplementation),
            address(airdropProxyAdmin),
            airdropInitializeData
        );

        // Airdrop Proxy Admin Owner 변경
        airdropProxyAdmin.transferOwnership(_foundation);

        airdropContract = FncyTokenAirdrop(address(airdropProxy));

        // 에어드랍 컨트랙트 Owner 변경
        airdropContract.transferOwnership(_foundation);

        vm.stopPrank();
    }

    // ==========================================
    // 초기 상태 검증 테스트
    // ==========================================

    // @dev 에어드랍 컨트랙트 배포 직후 초기 executor 권한 체크
    function test_CheckInitExecutor() public view {
        bool isExecutor = airdropContract.isExecutor(_executor);
        address[] memory executors = airdropContract.getExecutors();
        assertEq(isExecutor, true);
        assertEq(executors.length, 2); // _developer, _executor
        assertEq(executors[0], _developer);
        assertEq(executors[1], _executor);
    }

    // @dev 에어드랍 컨트랙트 배포 직후 초기 상태 체크
    function test_CheckInitAirdropStats() public view {
        (uint256 totalExecuted, uint256 totalRecipients, uint256 totalAmount) = airdropContract.getAirdropStatus();
        assertEq(totalExecuted, 0);
        assertEq(totalRecipients, 0);
        assertEq(totalAmount, 0);

        uint256 airdropLimit = airdropContract.getAirdropLimit();
        assertEq(airdropLimit, type(uint256).max);
    }

    // @dev 에어드랍 컨트랙트 배포 직후 토큰 주소 체크
    function test_CheckInitTargetToken() public view {
        uint256 contractBalance = airdropContract.getContractTokenBalance();
        assertEq(contractBalance, 0);
    }

    // ==========================================
    // Executor 권한 관리 테스트
    // ==========================================

    // @dev Executor 권한 추가
    function test_AddExecutor() public {
        vm.startPrank(_foundation);
        _addExecutor(_minter);
        _addExecutor(_user1);

        bool isExecutorMinter = airdropContract.isExecutor(_minter);
        bool isExecutorUser1 = airdropContract.isExecutor(_user1);
        assertEq(isExecutorMinter, true, "Add Minter as Executor");
        assertEq(isExecutorUser1, true, "Add User1 as Executor");

        address[] memory executors = airdropContract.getExecutors();
        assertEq(executors[0], _developer);
        assertEq(executors[1], _executor);
        assertEq(executors[2], _minter);

        vm.stopPrank();
    }

    // @dev Executor 권한 제거
    function test_RemoveExecutor() public {
        vm.startPrank(_foundation);
        _removeExecutor(_developer);
        _removeExecutor(_executor);

        bool isExecutor = airdropContract.isExecutor(_executor);
        assertEq(isExecutor, false);
        bool isExecutorDeveloper = airdropContract.isExecutor(_developer);
        assertEq(isExecutorDeveloper, false);

        address[] memory executors = airdropContract.getExecutors();
        assertEq(executors.length, 0);

        vm.stopPrank();
    }

    // @dev Executor 권한 추가 실패 - 오너가 아님
    function test_AddExecutorNotOwnerReverts() public {
        vm.startPrank(_developer);
        vm.expectRevert("Ownable: caller is not the owner");
        _addExecutor(_minter);
        vm.stopPrank();
    }

    // @dev Executor 권한 제거 실패 - 오너가 아님
    function test_RemoveExecutorNotOwnerReverts() public {
        vm.startPrank(_developer);
        vm.expectRevert("Ownable: caller is not the owner");
        _removeExecutor(_executor);
        vm.stopPrank();
    }

    // ==========================================
    // 개별 에어드랍 테스트 (Executor 토큰 사용)
    // ==========================================

    // @dev 개별 에어드랍 - Success
    function test_Airdrop() public {
        // 테스트 준비: executor에게 토큰 전송 및 approve
        vm.startPrank(_foundation);
        uint256 transferAmount = 10_000 ether;
        fncyToken.transfer(_executor, transferAmount);
        vm.stopPrank();

        vm.startPrank(_executor);
        fncyToken.approve(address(airdropContract), transferAmount);

        // 초기 상태 확인
        uint256 initialExecutorBalance = fncyToken.balanceOf(_executor);
        uint256 initialUser1Balance = fncyToken.balanceOf(_user1);

        // 에어드랍 실행
        uint256 airdropAmount = 1_000 ether;
        airdropContract.airdrop(_executor, _user1, airdropAmount);

        // 에어드랍 후 상태 확인
        uint256 finalExecutorBalance = fncyToken.balanceOf(_executor);
        uint256 finalUser1Balance = fncyToken.balanceOf(_user1);

        // 검증
        assertEq(finalExecutorBalance, initialExecutorBalance - airdropAmount);
        assertEq(finalUser1Balance, initialUser1Balance + airdropAmount);

        // 통계 확인
        (uint256 totalExecuted, uint256 totalRecipients, uint256 totalAmount) = airdropContract.getAirdropStatus();
        assertEq(totalExecuted, 1);
        assertEq(totalRecipients, 1);
        assertEq(totalAmount, airdropAmount);

        uint256 receivedAmount = airdropContract.getReceivedAmount(_user1);
        assertEq(receivedAmount, airdropAmount);

        vm.stopPrank();
    }

    // @dev 배치 에어드랍 - Success
    function test_BatchAirdrop() public {
        // 테스트 준비: executor에게 토큰 전송 및 approve
        vm.startPrank(_foundation);
        uint256 transferAmount = 10_000 ether;
        fncyToken.transfer(_executor, transferAmount);
        vm.stopPrank();

        vm.startPrank(_executor);
        fncyToken.approve(address(airdropContract), transferAmount);

        // 배치 에어드랍 데이터 준비
        address[] memory recipients = new address[](3);
        recipients[0] = _user1;
        recipients[1] = _user2;
        recipients[2] = _user3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1_000 ether;
        amounts[1] = 2_000 ether;
        amounts[2] = 1_500 ether;

        uint256 totalAirdropAmount = amounts[0] + amounts[1] + amounts[2];

        // 초기 상태 확인
        uint256 initialExecutorBalance = fncyToken.balanceOf(_executor);

        // 배치 에어드랍 실행
        address[] memory froms = new address[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            froms[i] = _executor;
        }
        airdropContract.batchAirdrop(froms, recipients, amounts);

        // 에어드랍 후 상태 확인
        uint256 finalExecutorBalance = fncyToken.balanceOf(_executor);
        uint256 user1Balance = fncyToken.balanceOf(_user1);
        uint256 user2Balance = fncyToken.balanceOf(_user2);
        uint256 user3Balance = fncyToken.balanceOf(_user3);

        // 검증
        assertEq(finalExecutorBalance, initialExecutorBalance - totalAirdropAmount);
        assertEq(user1Balance, amounts[0]);
        assertEq(user2Balance, amounts[1]);
        assertEq(user3Balance, amounts[2]);

        // 통계 확인
        (uint256 totalExecuted, uint256 totalRecipients, uint256 totalAmount) = airdropContract.getAirdropStatus();
        assertEq(totalExecuted, 3);
        assertEq(totalRecipients, 3);
        assertEq(totalAmount, totalAirdropAmount);

        vm.stopPrank();
    }

    // @dev 에어드랍 실패 - Executor 권한 없음
    function test_AirdropFailNotExecutor() public {
        vm.startPrank(_user1);
        vm.expectPartialRevert(IFncyTokenAirdrop.UnauthorizedAirdropExecute.selector);
        airdropContract.airdrop(_executor, _user2, 1 ether);
        vm.stopPrank();
    }

    // @dev 에어드랍 실패 - Allowance 부족
    function test_AirdropFailInsufficientAllowance() public {
        // 테스트 준비: executor에게 토큰 전송 (approve는 하지 않음)
        vm.startPrank(_foundation);
        uint256 transferAmount = 10_000 ether;
        fncyToken.transfer(_executor, transferAmount);
        vm.stopPrank();

        vm.startPrank(_executor);
        vm.expectPartialRevert(IFncyTokenAirdrop.InsufficientAllowance.selector);
        airdropContract.airdrop(_executor, _user1, 1_000 ether);
        vm.stopPrank();
    }

    // ==========================================
    // 풀 에어드랍 테스트 (컨트랙트 토큰 사용)
    // ==========================================

    // @dev 풀에 토큰 입금
    function test_DepositToPool() public {
        vm.startPrank(_foundation);
        uint256 depositAmount = 50_000 ether;

        // approve 후 입금
        fncyToken.approve(address(airdropContract), depositAmount);
        airdropContract.depositToPool(depositAmount);

        // 검증
        uint256 contractBalance = airdropContract.getContractTokenBalance();
        assertEq(contractBalance, depositAmount);

        vm.stopPrank();
    }

    // @dev 풀에서 개별 에어드랍
    function test_AirdropFromPool() public {
        // 테스트 준비: 풀에 토큰 입금
        vm.startPrank(_foundation);
        uint256 depositAmount = 50_000 ether;
        fncyToken.approve(address(airdropContract), depositAmount);
        airdropContract.depositToPool(depositAmount);
        vm.stopPrank();

        // 풀 에어드랍 실행
        vm.startPrank(_executor);
        uint256 airdropAmount = 5_000 ether;
        uint256 initialUser1Balance = fncyToken.balanceOf(_user1);
        uint256 initialContractBalance = airdropContract.getContractTokenBalance();

        airdropContract.airdropFromPool(_user1, airdropAmount);

        // 검증
        uint256 finalUser1Balance = fncyToken.balanceOf(_user1);
        uint256 finalContractBalance = airdropContract.getContractTokenBalance();

        assertEq(finalUser1Balance, initialUser1Balance + airdropAmount);
        assertEq(finalContractBalance, initialContractBalance - airdropAmount);

        vm.stopPrank();
    }

    // @dev 풀에서 배치 에어드랍
    function test_BatchAirdropFromPool() public {
        // 테스트 준비: 풀에 토큰 입금
        vm.startPrank(_foundation);
        uint256 depositAmount = 50_000 ether;
        fncyToken.approve(address(airdropContract), depositAmount);
        airdropContract.depositToPool(depositAmount);
        vm.stopPrank();

        // 배치 에어드랍 데이터 준비
        address[] memory recipients = new address[](3);
        recipients[0] = _user1;
        recipients[1] = _user2;
        recipients[2] = _user3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 2_000 ether;
        amounts[1] = 3_000 ether;
        amounts[2] = 2_500 ether;

        uint256 totalAirdropAmount = amounts[0] + amounts[1] + amounts[2];

        // 풀 배치 에어드랍 실행
        vm.startPrank(_executor);
        uint256 initialContractBalance = airdropContract.getContractTokenBalance();

        airdropContract.batchAirdropFromPool(recipients, amounts);

        // 검증
        uint256 finalContractBalance = airdropContract.getContractTokenBalance();
        uint256 user1Balance = fncyToken.balanceOf(_user1);
        uint256 user2Balance = fncyToken.balanceOf(_user2);
        uint256 user3Balance = fncyToken.balanceOf(_user3);

        assertEq(finalContractBalance, initialContractBalance - totalAirdropAmount);
        assertEq(user1Balance, amounts[0]);
        assertEq(user2Balance, amounts[1]);
        assertEq(user3Balance, amounts[2]);

        vm.stopPrank();
    }

    // @dev 풀 에어드랍 실패 - 컨트랙트 잔액 부족
    function test_AirdropFromPoolFailInsufficientBalance() public {
        vm.startPrank(_executor);
        vm.expectPartialRevert(IFncyTokenAirdrop.InsufficientContractBalance.selector);
        airdropContract.airdropFromPool(_user1, 1_000 ether);
        vm.stopPrank();
    }

    // @dev 풀에서 토큰 출금
    function test_WithdrawFromPool() public {
        // 테스트 준비: 풀에 토큰 입금
        vm.startPrank(_foundation);
        uint256 depositAmount = 50_000 ether;
        fncyToken.approve(address(airdropContract), depositAmount);
        airdropContract.depositToPool(depositAmount);

        // 출금 전 상태 확인
        uint256 initialFoundationBalance = fncyToken.balanceOf(_foundation);
        uint256 initialContractBalance = airdropContract.getContractTokenBalance();

        // 출금 실행
        uint256 withdrawAmount = 20_000 ether;
        airdropContract.withdrawFromPool(withdrawAmount);

        // 검증
        uint256 finalFoundationBalance = fncyToken.balanceOf(_foundation);
        uint256 finalContractBalance = airdropContract.getContractTokenBalance();

        assertEq(finalFoundationBalance, initialFoundationBalance + withdrawAmount);
        assertEq(finalContractBalance, initialContractBalance - withdrawAmount);

        vm.stopPrank();
    }

    // ==========================================
    // 제한량 관리 테스트
    // ==========================================

    // @dev 에어드랍 제한량 설정
    function test_SetAirdropLimit() public {
        vm.startPrank(_foundation);
        uint256 newLimit = 100_000 ether;
        airdropContract.setAirdropLimit(newLimit);

        uint256 airdropLimit = airdropContract.getAirdropLimit();
        assertEq(airdropLimit, newLimit);

        uint256 remainingAmount = airdropContract.getRemainingAirdropAmount();
        assertEq(remainingAmount, newLimit);

        vm.stopPrank();
    }

    // @dev 에어드랍 제한량 초과 실패
    function test_AirdropFailMaxLimitExceeded() public {
        // 제한량 설정
        vm.startPrank(_foundation);
        uint256 limitAmount = 5_000 ether;
        airdropContract.setAirdropLimit(limitAmount);

        // executor에게 토큰 전송 및 approve
        fncyToken.transfer(_executor, 10_000 ether);
        vm.stopPrank();

        vm.startPrank(_executor);
        fncyToken.approve(address(airdropContract), 10_000 ether);

        // 제한량 초과 에어드랍 시도
        vm.expectPartialRevert(IFncyTokenAirdrop.MaxAirdropLimitExceeded.selector);
        airdropContract.airdrop(_executor, _user1, limitAmount + 1 ether);

        vm.stopPrank();
    }

    // ==========================================
    // 배치 크기 제한 테스트
    // ==========================================

    // @dev 배치 크기 초과 실패
    function test_BatchAirdropFailSizeTooLarge() public {
        vm.startPrank(_executor);

        // MAX_BATCH_SIZE보다 큰 배열 생성
        address[] memory recipients = new address[](MAX_BATCH_SIZE + 1);
        uint256[] memory amounts = new uint256[](MAX_BATCH_SIZE + 1);

        for (uint256 i = 0; i < MAX_BATCH_SIZE + 1; i++) {
            recipients[i] = address(uint160(i + 100));
            amounts[i] = 1 ether;
        }

        address[] memory froms = new address[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            froms[i] = _executor;
        }

        vm.expectPartialRevert(IFncyTokenAirdrop.BatchSizeTooLarge.selector);
        airdropContract.batchAirdrop(froms, recipients, amounts);

        vm.stopPrank();
    }

    // ==========================================
    // 타겟 토큰 변경 테스트
    // ==========================================

    // @dev 타겟 토큰 변경
    function test_ChangeTargetToken() public {
        // 새로운 토큰 배포
        vm.startPrank(_developer);
        FncyToken newToken = new FncyToken();
        vm.stopPrank();

        // 타겟 토큰 변경
        vm.startPrank(_foundation);
        airdropContract.changeTargetToken(address(newToken));

        // 검증 (새 토큰의 잔액은 0이어야 함)
        uint256 newTokenBalance = airdropContract.getContractTokenBalance();
        assertEq(newTokenBalance, 0);

        vm.stopPrank();
    }

    // ==========================================
    // 헬퍼 함수
    // ==========================================

    function _addExecutor(address executor) internal {
        airdropContract.addAirdropExecutor(executor);
    }

    function _removeExecutor(address executor) internal {
        airdropContract.removeAirdropExecutor(executor);
    }
}