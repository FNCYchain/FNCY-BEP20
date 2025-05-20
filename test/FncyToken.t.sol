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

    uint256 public MAX_SUPPLY = 2_000_000_000 ether;

    // 실제 배포 순서에 관해 다룸
    function setUp() public {
        vm.startPrank(_developer);
        // 1. Proxy Admin 배포
        proxyAdmin = _deployProxyAdmin();

        // 2. 토큰 컨트랙트 배포 (프록시 구현체)
        _implementation = _deployFncyTokenContract();

        // 3. Proxy 배포 (Transparent)
        bytes memory initializeData = abi.encodeWithSignature("initialize()");
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

    function test_CheckInitMint() public {
        uint256 balance = fncyToken.balanceOf(_foundation);
        assertEq(balance, 2_000_000_000 ether);
    }

    function test_RemoveMinter() public {
        vm.startPrank(_foundation);
        fncyToken.removeMinter(_developer);
        bool isMinter = fncyToken.isMinter(_developer);
        assertEq(isMinter, false);
    }

    function test_AddMinter() public {
        vm.startPrank(_foundation);
        fncyToken.addMinter(_foundation);
        fncyToken.addMinter(_minter);
        bool isMinterNewMinter = fncyToken.isMinter(_minter);
        bool isMinterFoundation = fncyToken.isMinter(_minter);
        assertEq(isMinterNewMinter, true, "Add New Minter");
        assertEq(isMinterFoundation, true, "Add Foundation");
    }

    function test_softBurn() public {
        vm.startPrank(_foundation);
        uint256 senderBalanceBefore = fncyToken.balanceOf(_foundation);
        uint256 lockAmount = 1_000_000_000 ether;
        fncyToken.lock(lockAmount);

        uint256 senderBalanceAfter = fncyToken.balanceOf(_foundation);
        uint256 contractBalance = fncyToken.balanceOf(address(fncyToken));

        assertEq(senderBalanceAfter, senderBalanceBefore - lockAmount);
        assertEq(contractBalance, lockAmount);

        // check total supply
        assertEq(MAX_SUPPLY, fncyToken.totalSupply());
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
}