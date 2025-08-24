// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {FncyNFT} from "../src/FncyNFT.sol";
import {IFncyNFT} from "../src/interfaces/IFncyNFT.sol";
import {Test, console} from "forge-std/Test.sol";

contract FncyNFTTest is Test {
    FncyNFT                     public fncyNFT;
    FncyNFT                     public _implementation;
    ProxyAdmin                  public proxyAdmin;
    TransparentUpgradeableProxy public proxy;

    address public _developer   = address(1); // 개발자, 초기 배포자
    address public _foundation  = address(2); // 재단
    address public _minter      = address(3); // 민팅용 주소
    address public _creator     = address(4); // NFT 크리에이터
    address public _user1       = address(5); // 일반 사용자 1
    address public _user2       = address(6); // 일반 사용자 2

    uint256 public MAX_SUPPLY = 1_000_000_000_000;
    uint256 public MAX_BATCH_SIZE = 500;

    string constant BASE_URI = "https://api.fncy.world/nft/";

    // 실제 배포 순서에 관해 다룸
    function setUp() public {
        vm.startPrank(_developer);

        // 1. Proxy Admin 배포
        proxyAdmin = _deployProxyAdmin();

        // 2. NFT 컨트랙트 배포 (프록시 구현체)
        _implementation = _deployFncyNFTContract();

        // 3. Proxy 배포 (Transparent)
        bytes memory initializeData = abi.encodeWithSignature(
            "initialize(string,string,string)",
            "FNCY NFT",
            "FNFT",
            BASE_URI
        );
        proxy = _deployTransparentProxy(
            address(_implementation),
            address(proxyAdmin),
            initializeData
        );

        // 4. Proxy Admin Owner 변경
        proxyAdmin.transferOwnership(_foundation);

        fncyNFT = FncyNFT(address(proxy));

        // 5. NFT Owner 변경
        fncyNFT.transferOwnership(_foundation);

        vm.stopPrank();
    }

    // ==========================================
    // 초기 상태 검증 테스트
    // ==========================================

    // @dev 컨트랙트 배포 직후 개발자 주소 민팅 권한 & 데이터 존재 체크
    function test_CheckInitMintingPermAndData() public view {
        bool isMinter = _isMinter(_developer);
        address[] memory minters = fncyNFT.getMinters();

        assertEq(isMinter, true);
        assertEq(minters.length, 1);
        assertEq(minters[0], _developer);
    }

    // @dev 컨트랙트 배포 직후 소각량 체크
    function test_CheckInitTotalBurned() public view {
        uint256 totalBurned = fncyNFT.getTotalBurned();
        assertEq(totalBurned, 0);
    }

    // @dev 컨트랙트 배포 직후 최대 공급량 체크
    function test_CheckInitMaxSupply() public view {
        uint256 maxSupply = fncyNFT.getMaxSupply();
        assertEq(maxSupply, MAX_SUPPLY);
    }

    // ==========================================
    // Minter 권한 관리 테스트
    // ==========================================

    // @dev 민터 권한 추가
    function test_AddMinter() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);
        _addMinter(_minter);

        bool isMinterFoundation = _isMinter(_foundation);
        bool isMinterNewMinter = _isMinter(_minter);

        assertEq(isMinterFoundation, true, "Add Foundation as Minter");
        assertEq(isMinterNewMinter, true, "Add New Minter");

        address[] memory minters = fncyNFT.getMinters();
        assertEq(minters.length, 3);
        assertEq(minters[0], _developer);
        assertEq(minters[1], _foundation);
        assertEq(minters[2], _minter);

        vm.stopPrank();
    }

    // @dev 민터 권한 제거
    function test_RemoveMinter() public {
        vm.startPrank(_foundation);
        _removeMinter(_developer);

        bool isMinter = _isMinter(_developer);
        assertEq(isMinter, false);

        address[] memory minters = fncyNFT.getMinters();
        assertEq(minters.length, 0);

        vm.stopPrank();
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
        _removeMinter(_developer);
        vm.stopPrank();
    }

    // ==========================================
    // NFT 발행 테스트
    // ==========================================

    // @dev 개별 NFT 발행 - Success
    function test_Minting() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);

        uint256 tokenId = 1;
        string memory tokenURI = "metadata/1.json";

        // NFT 발행
        _mint(_user1, tokenId, tokenURI);

        // 발행 후 상태 확인
        address owner = fncyNFT.ownerOf(tokenId);

        // 검증
        assertEq(owner, _user1);

        vm.stopPrank();
    }

    // @dev 배치 NFT 발행 - Success
    function test_BatchMinting() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;

        string[] memory tokenURIs = new string[](3);
        tokenURIs[0] = "metadata/1.json";
        tokenURIs[1] = "metadata/2.json";
        tokenURIs[2] = "metadata/3.json";
        // 배치 발행
        _batchMint(_user1, tokenIds, tokenURIs);

        // 각 토큰 소유자 확인
        for (uint256 i = 0; i < tokenIds.length; i++) {
            address owner = fncyNFT.ownerOf(tokenIds[i]);
            assertEq(owner, _user1);
        }

        vm.stopPrank();
    }

    // @dev NFT 발행 실패 - Minter 권한 없음
    function test_MintingFailNotMinter() public {
        vm.startPrank(_minter);
        vm.expectPartialRevert(IFncyNFT.UnauthorizedMinting.selector);
        _mint(_user1, 1, "metadata/1.json");
        vm.stopPrank();
    }

    // @dev 배치 NFT 발행 실패 - 배치 크기 초과
    function test_BatchMintingFailSizeTooLarge() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);

        // MAX_BATCH_SIZE보다 큰 배열 생성
        uint256[] memory tokenIds = new uint256[](MAX_BATCH_SIZE + 1);
        string[] memory tokenURIs = new string[](MAX_BATCH_SIZE + 1);

        for (uint256 i = 0; i < MAX_BATCH_SIZE + 1; i++) {
            tokenIds[i] = i + 1;
            tokenURIs[i] = string(abi.encodePacked("metadata/", vm.toString(i + 1), ".json"));
        }

        vm.expectPartialRevert(IFncyNFT.BatchSizeTooLarge.selector);
        _batchMint(_user1, tokenIds, tokenURIs);

        vm.stopPrank();
    }

    // @dev 배치 NFT 발행 실패 - 배열 크기 불일치
    function test_BatchMintingFailSizeMismatch() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;

        string[] memory tokenURIs = new string[](2); // 크기 다름
        tokenURIs[0] = "metadata/1.json";
        tokenURIs[1] = "metadata/2.json";

        vm.expectPartialRevert(IFncyNFT.BatchSizeMismatch.selector);
        _batchMint(_user1, tokenIds, tokenURIs);

        vm.stopPrank();
    }

    // ==========================================
    // NFT 소각 테스트
    // ==========================================

    // @dev 개별 NFT 소각 - Success
    function test_Burn() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);

        // 먼저 NFT 발행
        uint256 tokenId = 1;
        _mint(_user1, tokenId, "metadata/1.json");

        uint256 initialTotalBurned = fncyNFT.getTotalBurned();

        // NFT 소각
        _burn(tokenId);

        // 소각 후 상태 확인
        uint256 finalTotalBurned = fncyNFT.getTotalBurned();

        assertEq(finalTotalBurned, initialTotalBurned + 1);

        // 토큰이 존재하지 않는지 확인
        vm.expectRevert("ERC721: invalid token ID");
        fncyNFT.ownerOf(tokenId);

        vm.stopPrank();
    }

    // @dev 배치 NFT 소각 - Success
    function test_BatchBurn() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);

        // 먼저 NFT들 발행
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;

        string[] memory tokenURIs = new string[](3);
        tokenURIs[0] = "metadata/1.json";
        tokenURIs[1] = "metadata/2.json";
        tokenURIs[2] = "metadata/3.json";

        _batchMint(_user1, tokenIds, tokenURIs);

        uint256 initialTotalBurned = fncyNFT.getTotalBurned();

        // 배치 소각
        _batchBurn(tokenIds);

        // 소각 후 상태 확인
        uint256 finalTotalBurned = fncyNFT.getTotalBurned();

        // 검증
        assertEq(finalTotalBurned, initialTotalBurned + 3);

        vm.stopPrank();
    }

    // @dev NFT 소각 실패 - Minter 권한 없음
    function test_BurnFailNotMinter() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);
        _mint(_user1, 1, "metadata/1.json");
        vm.stopPrank();

        vm.startPrank(_minter);
        vm.expectPartialRevert(IFncyNFT.UnauthorizedMinting.selector);
        _burn(1);
        vm.stopPrank();
    }

    // @dev NFT 소각 실패 - 토큰이 존재하지 않음
    function test_BurnFailTokenNotExists() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);

        vm.expectPartialRevert(IFncyNFT.TokenNotExists.selector);
        _burn(999);

        vm.stopPrank();
    }

    // @dev 배치 소각 실패 - 배치 크기 초과
    function test_BatchBurnFailSizeTooLarge() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);

        // MAX_BATCH_SIZE보다 큰 배열 생성
        uint256[] memory tokenIds = new uint256[](MAX_BATCH_SIZE + 1);

        for (uint256 i = 0; i < MAX_BATCH_SIZE + 1; i++) {
            tokenIds[i] = i + 1;
        }

        vm.expectPartialRevert(IFncyNFT.BatchSizeTooLarge.selector);
        _batchBurn(tokenIds);

        vm.stopPrank();
    }

    // ==========================================
    // URI 관리 테스트
    // ==========================================

    // @dev 베이스 URI 설정
    function test_SetBaseURI() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);
        _mint(_user1, 1, "metadata/1.json");

        string memory newBaseURI = "https://new-api.fncy.world/nft/";
        fncyNFT.setBaseURI(newBaseURI);

        string memory tokenURI = fncyNFT.tokenURI(1);
        assertEq(tokenURI, string(abi.encodePacked(newBaseURI, "metadata/1.json")));

        vm.stopPrank();
    }

    // @dev 개별 토큰 URI 설정
    function test_SetTokenURI() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);
        _mint(_user1, 1, "metadata/1.json");

        string memory newTokenURI = "special/metadata.json";
        fncyNFT.setTokenURI(1, newTokenURI);

        string memory tokenURI = fncyNFT.tokenURI(1);
        assertEq(tokenURI, string(abi.encodePacked(BASE_URI, newTokenURI)));

        vm.stopPrank();
    }

    // @dev URI 설정 실패 - 오너가 아님
    function test_SetBaseURIFailNotOwner() public {
        vm.startPrank(_developer);
        vm.expectRevert("Ownable: caller is not the owner");
        fncyNFT.setBaseURI("https://new-api.fncy.world/nft/");
        vm.stopPrank();
    }

    // @dev 토큰 URI 설정 실패 - 토큰이 존재하지 않음
    function test_SetTokenURIFailTokenNotExists() public {
        vm.startPrank(_foundation);
        vm.expectPartialRevert(IFncyNFT.TokenNotExists.selector);
        fncyNFT.setTokenURI(999, "metadata.json");
        vm.stopPrank();
    }

    // ==========================================
    // NFT 전송 테스트
    // ==========================================

    // @dev NFT 전송 - Success
    function test_Transfer() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);
        _mint(_user1, 1, "metadata/1.json");
        vm.stopPrank();

        vm.startPrank(_user1);

        // 전송 전 소유자 확인
        address initialOwner = fncyNFT.ownerOf(1);
        assertEq(initialOwner, _user1);

        // NFT 전송
        fncyNFT.transferFrom(_user1, _user2, 1);

        // 전송 후 소유자 확인
        address finalOwner = fncyNFT.ownerOf(1);
        assertEq(finalOwner, _user2);

        vm.stopPrank();
    }

    // ==========================================
    // 통합 테스트
    // ==========================================

    // @dev 발행, 전송, 소각 통합 테스트
    function test_MintTransferBurnIntegration() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);

        // 1. NFT 발행
        uint256 tokenId = 1;
        _mint(_user1, tokenId, "metadata/1.json");
        address owner = fncyNFT.ownerOf(tokenId);
        assertEq(owner, _user1);

        vm.stopPrank();

        vm.startPrank(_user1);

        // 2. NFT 전송
        fncyNFT.transferFrom(_user1, _user2, tokenId);
        address newOwner = fncyNFT.ownerOf(tokenId);
        assertEq(newOwner, _user2);

        vm.stopPrank();

        vm.startPrank(_foundation);

        // 3. NFT 소각
        uint256 initialTotalBurned = fncyNFT.getTotalBurned();
        _burn(tokenId);
        uint256 finalTotalBurned = fncyNFT.getTotalBurned();

        assertEq(finalTotalBurned, initialTotalBurned + 1);

        // 토큰이 존재하지 않는지 확인
        vm.expectRevert("ERC721: invalid token ID");
        fncyNFT.ownerOf(tokenId);

        vm.stopPrank();
    }

    // @dev 대량 발행 및 소각 테스트
    function test_LargeBatchMintAndBurn() public {
        vm.startPrank(_foundation);
        _addMinter(_foundation);

        // 대량 배치 데이터 준비 (500개)
        uint256 batchSize = MAX_BATCH_SIZE;
        uint256[] memory tokenIds = new uint256[](batchSize);
        string[] memory tokenURIs = new string[](batchSize);

        for (uint256 i = 0; i < batchSize; i++) {
            tokenIds[i] = i + 1;
            tokenURIs[i] = string(abi.encodePacked("metadata/", vm.toString(i + 1), ".json"));
        }

        // 대량 배치 발행
        _batchMint(_user1, tokenIds, tokenURIs);

        // 대량 배치 소각
        _batchBurn(tokenIds);

        // 소각 후 상태 확인
        uint256 totalBurned = fncyNFT.getTotalBurned();
        assertEq(totalBurned, batchSize);

        vm.stopPrank();
    }

    // ==========================================
    // 헬퍼 함수
    // ==========================================

    // @dev Deploy Proxy Admin
    function _deployProxyAdmin() internal returns(ProxyAdmin) {
        return new ProxyAdmin();
    }

    // @dev Deploy NFT Contract
    function _deployFncyNFTContract() internal returns(FncyNFT){
        return new FncyNFT();
    }

    // @dev Deploy Transparent Proxy
    function _deployTransparentProxy(
        address logic,
        address admin,
        bytes memory data
    ) internal returns(TransparentUpgradeableProxy) {
        return new TransparentUpgradeableProxy(logic, admin, data);
    }

    function _addMinter(address minter) internal {
        fncyNFT.addMinter(minter);
    }

    function _removeMinter(address minter) internal {
        fncyNFT.removeMinter(minter);
    }

    function _isMinter(address minter) internal view returns(bool) {
        return fncyNFT.isMinter(minter);
    }

    function _mint(address to, uint256 tokenId, string memory tokenURI) internal {
        fncyNFT.mint(to, tokenId, tokenURI);
    }

    function _batchMint(address to, uint256[] memory tokenIds, string[] memory tokenURIs) internal {
        fncyNFT.batchMint(to, tokenIds, tokenURIs);
    }

    function _burn(uint256 tokenId) internal {
        fncyNFT.burn(tokenId);
    }

    function _batchBurn(uint256[] memory tokenIds) internal {
        fncyNFT.batchBurn(tokenIds);
    }
}