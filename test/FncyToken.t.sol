// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {FncyToken} from "../src/FncyToken.sol";
import {IFncyToken} from "../src/interfaces/IFncyToken.sol";
import {Test, console} from "forge-std/Test.sol";


contract FncyTokenTest is Test {
    FncyToken                   public fncyToken;
    FncyToken                   public _implementation;
    ProxyAdmin                  public proxyAdmin;
    TransparentUpgradeableProxy public proxy;

    address public _developer   = address(1); // 개발자, 초기 배포자
    address public _foundation  = address(2); // 재단
    address public _minter      = address(3); // 민팅용 주소(재단도 가능)
    address private constant DEAD_ADDRESS = address(0x000000000000000000000000000000000000dEaD);

    uint256 public MAX_SUPPLY = 2_000_000_000 ether;

    // 실제 배포 순서에 관해 다룸
    function setUp() public {
        vm.startPrank(_developer);
        // 1. Proxy Admin 배포
        proxyAdmin = _deployProxyAdmin();

        // 2. 토큰 컨트랙트 배포 (프록시 구현체)
        _implementation = _deployFncyTokenContract();

        // 3. Proxy 배포 (Transparent)
        bytes memory initializeData = abi.encodeWithSignature("initialize(uint256)", 23_000_000);
        proxy = _deployTransparentProxy(
            address(_implementation),
            address(proxyAdmin),
            initializeData
        );

        // 4. Proxy Admin Owner 변경
        proxyAdmin.transferOwnership(_foundation);

        fncyToken = FncyToken(address(proxy));
        // 5. 재단에게 20억개 민팅
        fncyToken.mint(_foundation, MAX_SUPPLY);
        // 6. Owner()
        fncyToken.transferOwnership(_foundation);
        vm.stopPrank();
    }

    // @dev 컨트랙트 배포 직후 초기 발행 물량 체크
    function test_CheckInitMint() public view {
        uint256 balance = _balanceOf(_foundation);
        assertEq(balance, 2_000_000_000 ether);
    }

    // @dev 컨트랙트 배포 직후 개발자 주소 민팅 권한 & 데이터 존재 체크
    function test_CheckInitMintingPermAndData() public view {
        bool isMinter = _isMinter(_developer);
        address[] memory minters = fncyToken.getMinters();
        assertEq(isMinter, true);
        assertEq(minters.length, 1);
        assertEq(minters[0], _developer);
    }

    // @dev 컨트랙트 배포 직후 유통량 체크
    function test_CheckInitCirculating() public view {
        uint256 circulating = fncyToken.getCirculating();
        assertEq(circulating, MAX_SUPPLY);
    }

    // @dev 컨트랙트 배포 직후 소각량 체크
    function test_CheckInitTotalBurned() public view {
        uint256 totalBurned = fncyToken.getTotalBurned();
        assertEq(totalBurned, 0);
    }

    // @dev 민터 권한 추가
    function test_AddMinter() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);
        _addMinter(_minter);
        bool isMinterNewMinter = _isMinter(_minter);
        bool isMinterFoundation = _isMinter(_minter);
        assertEq(isMinterNewMinter, true, "Add New Minter");
        assertEq(isMinterFoundation, true, "Add Foundation");

        address[] memory minters = fncyToken.getMinters();

        assertEq(minters.length, 3);
        assertEq(minters[0], _developer);
        assertEq(minters[1], _foundation);
        assertEq(minters[2], _minter);
    }

    // @dev 민터 권한 제거
    function test_RemoveMinter() public {
        vm.startPrank(_foundation);
        _removeMinter(_developer);
        bool isMinter = _isMinter(_developer);
        assertEq(isMinter, false);

        address[] memory minters = fncyToken.getMinters();
        assertEq(minters.length, 0);
    }

    // @dev 민터 권한 추가 실패 - 오너가 아님
    function test_AddMinterNotOwnerReverts() public {
        vm.startPrank(_developer);
        vm.expectRevert("Ownable: caller is not the owner");
        _addMinter(_foundation);
        vm.stopPrank();
    }

    // @dev 민터 권한 제거 실패 - 오너가 아님
    function test_RemoveMinterNotOwnerReverts() public {
        vm.startPrank(_developer);
        vm.expectRevert("Ownable: caller is not the owner");
        _removeMinter(_foundation);
        vm.stopPrank();
    }

    // @dev Minting - Success
    function test_Minting() public {
        vm.startPrank(_foundation);
        // 민터 권한 추가
        _addMinter(_foundation);
        // 배포 시 20억개 배포 했으므로 소각 해야 정상 작동함
        uint256 burnAmount = 10_000 ether;
        _burn(_foundation, burnAmount);
        uint256 balance1 = _balanceOf(_foundation);
        assertEq(balance1, MAX_SUPPLY - burnAmount);
        assertEq(fncyToken.getTotalBurned(), burnAmount);
        assertEq(fncyToken.getCirculating(), MAX_SUPPLY - burnAmount);
        // 민팅
        uint256 mintAmount = 9_999 ether;
        _mint(_foundation, mintAmount);
        uint256 balance2 = _balanceOf(_foundation);
        assertEq(balance2, MAX_SUPPLY - burnAmount + mintAmount);
        assertEq(fncyToken.getCirculating(), MAX_SUPPLY - burnAmount + mintAmount);
    }
    // @dev Minting - Fail
    function test_MintingFailNotMinter() public {
        vm.startPrank(_minter);
        vm.expectPartialRevert(IFncyToken.UnauthorizedMinting.selector);
        _mint(_developer, 1 ether);
        vm.stopPrank();
    }

    // @dev Minting - Fail
    function test_MintingFailMaxSupplyExceeded() public {
        vm.startPrank(_developer);
        vm.expectPartialRevert(IFncyToken.MaxSupplyExceeded.selector);
        _mint(_developer, 1 ether);
        vm.stopPrank();
    }

    // @dev Burn - Success
    function test_Burn() public {
        vm.startPrank(_foundation);
        // 민터 권한 추가
        _addMinter(_foundation);

        // 초기 상태 확인
        uint256 initialBalance = _balanceOf(_foundation);
        uint256 initialCirculating = fncyToken.getCirculating();
        uint256 initialTotalBurned = fncyToken.getTotalBurned();

        // 소각 실행
        uint256 burnAmount = 5_000 ether;
        _burn(_foundation, burnAmount);

        // 소각 후 상태 확인
        uint256 balance = _balanceOf(_foundation);
        assertEq(balance, initialBalance - burnAmount);
        assertEq(fncyToken.getTotalBurned(), initialTotalBurned + burnAmount);
        assertEq(fncyToken.getCirculating(), initialCirculating - burnAmount);

        vm.stopPrank();
    }

    // @dev Burning - Fail (Not Minter)
    function test_BurningFailNotMinter() public {
        // _minter가 minter 권한이 없는 상태에서 테스트
        vm.startPrank(_minter);
        vm.expectPartialRevert(IFncyToken.UnauthorizedMinting.selector);
        _burn(_foundation, 1 ether);
        vm.stopPrank();
    }
    // @dev Burning - Fail (Invalid Parameter - Zero Amount)
    function test_BurningFailZeroAmount() public {
        vm.startPrank(_foundation);
        // 민터 권한 추가
        _addMinter(_foundation);

        // 0 amount로 소각 시도
        vm.expectPartialRevert(IFncyToken.InvalidParameter.selector);
        _burn(_foundation, 0);

        vm.stopPrank();
    }

    // @dev Burning - Fail (Insufficient Circulating)
    function test_BurningFailInsufficientCirculating() public {
        vm.startPrank(_foundation);
        // 민터 권한 추가
        _addMinter(_foundation);

        // 1. 우선 현재 총 유통량보다 작은 양을 소각
        uint256 circulatingAmount = fncyToken.getCirculating();
        uint256 burnAmount = circulatingAmount - 100 ether; // 총 유통량보다 작게 설정
        _burn(_foundation, burnAmount);

        // 2. 남은 유통량보다 큰 양을 소각 시도
        uint256 remainingCirculating = fncyToken.getCirculating();
        vm.expectPartialRevert(IFncyToken.InsufficientCirculating.selector);
        _burn(_foundation, remainingCirculating + 1 ether);

        vm.stopPrank();
    }

    // @dev Burning - Fail (Balance Exceeded)
    function test_BurningFailBalanceExceeded() public {
        vm.startPrank(_foundation);
        // 민터 권한 추가
        _addMinter(_foundation);
        fncyToken.transfer(_developer, 10000 ether);
        // 현재 잔액보다 많은 금액 소각 시도
        uint256 balance = _balanceOf(_foundation);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        _burn(_foundation, balance + 1 ether);

        vm.stopPrank();
    }

    // @dev Burning - Burn from Another Account
    function test_BurningFromAnotherAccount() public {
        vm.startPrank(_foundation);
        // 민터 권한 추가
        _addMinter(_foundation);

        // 다른 계정에 토큰 전송
        uint256 transferAmount = 10_000 ether;
        fncyToken.transfer(_developer, transferAmount);

        // 다른 계정의 초기 상태 확인
        uint256 initialDevBalance = _balanceOf(_developer);
        uint256 initialCirculating = fncyToken.getCirculating();
        uint256 initialTotalBurned = fncyToken.getTotalBurned();

        // 다른 계정에서 소각
        uint256 burnAmount = 5_000 ether;
        _burn(_developer, burnAmount);

        // 소각 후 상태 확인
        uint256 devBalance = _balanceOf(_developer);
        assertEq(devBalance, initialDevBalance - burnAmount);
        assertEq(fncyToken.getTotalBurned(), initialTotalBurned + burnAmount);
        assertEq(fncyToken.getCirculating(), initialCirculating - burnAmount);

        vm.stopPrank();
    }

    // @dev Lock - Success
    function test_Lock() public {
        // 테스트 계정에 토큰 전송 (테스트 전 셋업)
        vm.startPrank(_foundation);
        uint256 transferAmount = 10_000 ether;
        fncyToken.transfer(_developer, transferAmount);
        vm.stopPrank();

        // 실제 lock 테스트
        vm.startPrank(_developer);

        // 초기 상태 확인
        uint256 initialDevBalance = fncyToken.balanceOf(_developer);
        uint256 initialContractBalance = fncyToken.balanceOf(address(fncyToken));
        uint256 initialCirculating = fncyToken.getCirculating();

        // lock 실행
        uint256 lockAmount = 5_000 ether;
        fncyToken.lock(lockAmount);

        // lock 후 상태 확인
        uint256 finalDevBalance = fncyToken.balanceOf(_developer);
        uint256 finalContractBalance = fncyToken.balanceOf(address(fncyToken));
        uint256 finalCirculating = fncyToken.getCirculating();

        // 검증
        assertEq(finalDevBalance, initialDevBalance - lockAmount);
        assertEq(finalContractBalance, initialContractBalance + lockAmount);
        assertEq(finalCirculating, initialCirculating - lockAmount);

        vm.stopPrank();
    }

    // @dev Lock - Fail (Zero Amount)
    function test_LockFailZeroAmount() public {
        vm.startPrank(_developer);

        // 0 amount로 lock 시도
        vm.expectPartialRevert(IFncyToken.InvalidParameter.selector);
        fncyToken.lock(0);

        vm.stopPrank();
    }

    // @dev Lock - Fail (Insufficient Balance)
    function test_LockFailInsufficientBalance() public {
        vm.startPrank(_developer);

        // 현재 잔액 확인
        uint256 balance = fncyToken.balanceOf(_developer);

        // 잔액보다 많은 양 lock 시도
        vm.expectPartialRevert(IFncyToken.InsufficientBalance.selector);
        fncyToken.lock(balance + 1 ether);

        vm.stopPrank();
    }

    // @dev Lock - Lock with Exact Balance
    function test_LockExactBalance() public {
        // 테스트 계정에 토큰 전송 (테스트 전 셋업)
        vm.startPrank(_foundation);
        uint256 transferAmount = 5_000 ether;
        fncyToken.transfer(_developer, transferAmount);
        vm.stopPrank();

        vm.startPrank(_developer);

        // 초기 상태 확인
        uint256 initialDevBalance = fncyToken.balanceOf(_developer);
        uint256 initialContractBalance = fncyToken.balanceOf(address(fncyToken));
        uint256 initialCirculating = fncyToken.getCirculating();

        // 전체 잔액 lock
        fncyToken.lock(initialDevBalance);

        // lock 후 상태 확인
        uint256 finalDevBalance = fncyToken.balanceOf(_developer);
        uint256 finalContractBalance = fncyToken.balanceOf(address(fncyToken));
        uint256 finalCirculating = fncyToken.getCirculating();

        // 검증
        assertEq(finalDevBalance, 0);
        assertEq(finalContractBalance, initialContractBalance + initialDevBalance);
        assertEq(finalCirculating, initialCirculating - initialDevBalance);

        vm.stopPrank();
    }

    // @dev SoftBurn - Success
    function test_SoftBurnWithAdmin() public {
        // 테스트 준비: 컨트랙트에 토큰 락업
        vm.startPrank(_foundation);
        uint256 lockAmount = 10_000 ether;
        fncyToken.lock(lockAmount);

        // 초기 상태 확인
        uint256 initialContractBalance = fncyToken.balanceOf(address(fncyToken));
        uint256 initialDeadBalance = fncyToken.balanceOf(DEAD_ADDRESS);
        uint256 initialCirculating = fncyToken.getCirculating();
        uint256 initialTotalBurned = fncyToken.getTotalBurned();

        // 소프트번 실행
        uint256 softBurnAmount = 5_000 ether;
        fncyToken.softBurnWithAdmin(softBurnAmount);

        // 실행 후 상태 확인
        uint256 finalContractBalance = fncyToken.balanceOf(address(fncyToken));
        uint256 finalDeadBalance = fncyToken.balanceOf(DEAD_ADDRESS);
        uint256 finalCirculating = fncyToken.getCirculating();
        uint256 finalTotalBurned = fncyToken.getTotalBurned();

        // 검증
        assertEq(finalContractBalance, initialContractBalance - softBurnAmount);
        assertEq(finalDeadBalance, initialDeadBalance + softBurnAmount);
        assertEq(finalCirculating, initialCirculating - softBurnAmount);
        assertEq(finalTotalBurned, initialTotalBurned + softBurnAmount);

        vm.stopPrank();
    }

    // @dev SoftBurn - All Locked Tokens
    function test_SoftBurnAllLockedTokens() public {
        // 테스트 준비: 컨트랙트에 토큰 락업
        vm.startPrank(_foundation);
        uint256 lockAmount = 10_000 ether;
        fncyToken.lock(lockAmount);

        // 초기 상태 확인
        uint256 initialContractBalance = fncyToken.balanceOf(address(fncyToken));
        uint256 initialDeadBalance = fncyToken.balanceOf(DEAD_ADDRESS);
        uint256 initialCirculating = fncyToken.getCirculating();
        uint256 initialTotalBurned = fncyToken.getTotalBurned();

        // 모든 락업된 토큰 소프트번
        fncyToken.softBurnWithAdmin(initialContractBalance);

        // 실행 후 상태 확인
        uint256 finalContractBalance = fncyToken.balanceOf(address(fncyToken));
        uint256 finalDeadBalance = fncyToken.balanceOf(DEAD_ADDRESS);
        uint256 finalCirculating = fncyToken.getCirculating();
        uint256 finalTotalBurned = fncyToken.getTotalBurned();

        // 검증
        assertEq(finalContractBalance, 0);
        assertEq(finalDeadBalance, initialDeadBalance + initialContractBalance);
        assertEq(finalCirculating, initialCirculating - initialContractBalance);
        assertEq(finalTotalBurned, initialTotalBurned + initialContractBalance);

        vm.stopPrank();
    }

    // @dev SoftBurn - Fail (Not Owner)
    function test_SoftBurnFailNotOwner() public {
        // 테스트 준비: 컨트랙트에 토큰 락업
        vm.startPrank(_foundation);
        uint256 lockAmount = 10_000 ether;
        fncyToken.lock(lockAmount);
        vm.stopPrank();

        // 비소유자(개발자)가 소프트번 시도
        vm.startPrank(_developer);
        vm.expectRevert("Ownable: caller is not the owner");
        fncyToken.softBurnWithAdmin(1000 ether);
        vm.stopPrank();
    }

    // @dev SoftBurn - Fail (Zero Amount)
    function test_SoftBurnFailZeroAmount() public {
        vm.startPrank(_foundation);

        // 0 amount로 소프트번 시도
        vm.expectPartialRevert(IFncyToken.InvalidParameter.selector);
        fncyToken.softBurnWithAdmin(0);

        vm.stopPrank();
    }

    // @dev SoftBurn - Fail (Insufficient Balance)
    function test_SoftBurnFailInsufficientBalance() public {
        // 테스트 준비: 컨트랙트에 토큰 락업
        vm.startPrank(_foundation);
        uint256 lockAmount = 5_000 ether;
        fncyToken.lock(lockAmount);

        // 컨트랙트 잔액보다 많은 양 소프트번 시도
        uint256 contractBalance = fncyToken.balanceOf(address(fncyToken));
        vm.expectPartialRevert(IFncyToken.InsufficientBalance.selector);
        fncyToken.softBurnWithAdmin(contractBalance + 1 ether);

        vm.stopPrank();
    }

    // @dev SoftBurn - Lock and SoftBurn Integration
    function test_LockAndSoftBurnIntegration() public {
        vm.startPrank(_foundation);

        // 초기 상태 확인
        uint256 initialFoundationBalance = fncyToken.balanceOf(_foundation);
        uint256 initialCirculating = fncyToken.getCirculating();
        uint256 initialTotalBurned = fncyToken.getTotalBurned();

        // 1. 토큰 락업
        uint256 lockAmount = 10_000 ether;
        fncyToken.lock(lockAmount);

        // 락업 후 상태 확인
        uint256 midFoundationBalance = fncyToken.balanceOf(_foundation);
        uint256 contractBalance = fncyToken.balanceOf(address(fncyToken));
        uint256 midCirculating = fncyToken.getCirculating();

        assertEq(midFoundationBalance, initialFoundationBalance - lockAmount);
        assertEq(contractBalance, lockAmount);
        assertEq(midCirculating, initialCirculating - lockAmount);

        // 2. 소프트번 실행
        uint256 softBurnAmount = lockAmount;
        fncyToken.softBurnWithAdmin(softBurnAmount);

        // 소프트번 후 상태 확인
        uint256 finalContractBalance = fncyToken.balanceOf(address(fncyToken));
        uint256 finalDeadBalance = fncyToken.balanceOf(DEAD_ADDRESS);
        uint256 finalCirculating = fncyToken.getCirculating();
        uint256 finalTotalBurned = fncyToken.getTotalBurned();

        // 검증
        assertEq(finalContractBalance, 0);
        assertEq(finalDeadBalance, softBurnAmount);
        assertEq(finalCirculating, initialCirculating - lockAmount - softBurnAmount);
        assertEq(finalTotalBurned, initialTotalBurned + softBurnAmount);

        vm.stopPrank();
    }

    // @dev Deploy Proxy Admin
    function _deployProxyAdmin() internal returns(ProxyAdmin) {
        return new ProxyAdmin();
    }

    // @dev Deploy Token Contract
    function _deployFncyTokenContract() internal returns(FncyToken){
        return new FncyToken();
    }

    // @dev Deploy Transparent Proxy
    function _deployTransparentProxy(
        address logic,
        address admin,
        bytes memory data
    ) internal returns(TransparentUpgradeableProxy) {
        return new TransparentUpgradeableProxy(logic, admin, data);
    }

    function _balanceOf(address target) internal view returns(uint256) {
        return fncyToken.balanceOf(target);
    }

    function _addMinter(address minter) internal {
        fncyToken.addMinter(minter);
    }

    function _removeMinter(address minter) internal {
        fncyToken.removeMinter(minter);
    }

    function _isMinter(address minter) internal view returns(bool) {
        return fncyToken.isMinter(minter);
    }

    function _mint(address account, uint256 amount) internal {
        fncyToken.mint(account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        fncyToken.burn(account, amount);
    }

}