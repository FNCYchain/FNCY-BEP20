// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {FncyNFTDeployer} from "../src/FncyNFTDeployer.sol";
import {FncyNFT} from "../src/FncyNFT.sol";
import {IFncyNFT} from "../src/interfaces/IFncyNFT.sol";
import {Test, console} from "forge-std/Test.sol";

contract FncyNFTDeployerTest is Test {
    FncyNFTDeployer public deployer;

    address public _developer   = address(1); // 개발자, 초기 배포자
    address public _foundation  = address(2); // 재단
    address public _creator1    = address(3); // NFT 크리에이터 1
    address public _creator2    = address(4); // NFT 크리에이터 2
    address public _user1       = address(5); // 일반 사용자 1
    address public _user2       = address(6); // 일반 사용자 2

    string constant TEST_NAME_1 = "FNCY NFT Collection";
    string constant TEST_SYMBOL_1 = "FNFT";
    string constant TEST_BASE_URI_1 = "https://api.fncy.world/nft/";

    string constant TEST_NAME_2 = "FNCY Art Collection";
    string constant TEST_SYMBOL_2 = "FART";
    string constant TEST_BASE_URI_2 = "https://art.fncy.world/metadata/";

    function setUp() public {
        vm.startPrank(_developer);

        // Deployer 컨트랙트 배포
        deployer = new FncyNFTDeployer();

        // Deployer Owner 변경
        deployer.transferOwnership(_foundation);

        vm.stopPrank();
    }

    // ==========================================
    // 초기 상태 검증 테스트
    // ==========================================

    // @dev Deployer 컨트랙트 배포 직후 초기 상태 체크
    function test_CheckInitDeployerState() public view {
        uint256 totalDeployed = deployer.getTotalDeployedCount();
        assertEq(totalDeployed, 0);

        address[] memory creator1Contracts = deployer.getContractsByCreator(_creator1);
        assertEq(creator1Contracts.length, 0);
    }

    // ==========================================
    // 기본 NFT 배포 테스트
    // ==========================================

    // @dev 기본 NFT 배포 - Success (새로운 ProxyAdmin)
    function test_DeployFncyNFT() public {
        vm.startPrank(_creator1);

        // NFT 배포
        (address proxyAdmin, address proxy, address implementation) = deployer.deployFncyNFT(
            TEST_NAME_1,
            TEST_SYMBOL_1,
            TEST_BASE_URI_1,
            address(0), // 새로운 ProxyAdmin 생성
            _creator1
        );

        // 배포 결과 검증
        assertTrue(proxyAdmin != address(0));
        assertTrue(proxy != address(0));
        assertTrue(implementation != address(0));

        // NFT 컨트랙트 기본 정보 확인
        FncyNFT nftContract = FncyNFT(proxy);
        assertEq(nftContract.name(), TEST_NAME_1);
        assertEq(nftContract.symbol(), TEST_SYMBOL_1);
        assertEq(nftContract.owner(), _creator1);

        // ProxyAdmin 소유권 확인
        ProxyAdmin adminContract = ProxyAdmin(proxyAdmin);
        assertEq(adminContract.owner(), _creator1);

        // 배포 통계 확인
        uint256 totalDeployed = deployer.getTotalDeployedCount();
//        assertEq(totalDeployed, 1);

        address[] memory creator1Contracts = deployer.getContractsByCreator(_creator1);
//        assertEq(creator1Contracts.length, 1);
//        assertEq(creator1Contracts[0], proxy);

        vm.stopPrank();
    }

    // @dev 기본 NFT 배포 - Success (기존 ProxyAdmin 재사용)
    function test_DeployFncyNFTWithExistingProxyAdmin() public {
        // 1. 첫 번째 NFT 배포 (새로운 ProxyAdmin 생성)
        vm.startPrank(_creator1);
        (address proxyAdmin1, address proxy1, ) = deployer.deployFncyNFT(
            TEST_NAME_1,
            TEST_SYMBOL_1,
            TEST_BASE_URI_1,
            address(0),
            _creator1
        );
        vm.stopPrank();

        // 2. 두 번째 NFT 배포 (기존 ProxyAdmin 재사용)
        vm.startPrank(_creator2);
        (address proxyAdmin2, address proxy2, address implementation2) = deployer.deployFncyNFT(
            TEST_NAME_2,
            TEST_SYMBOL_2,
            TEST_BASE_URI_2,
            proxyAdmin1, // 기존 ProxyAdmin 재사용
            _creator2
        );

        // 검증
        assertEq(proxyAdmin2, proxyAdmin1); // 동일한 ProxyAdmin 사용
        assertTrue(proxy2 != proxy1); // 다른 프록시 주소
        assertTrue(implementation2 != address(0));

        // 두 번째 NFT 컨트랙트 정보 확인
        FncyNFT nftContract2 = FncyNFT(proxy2);
        assertEq(nftContract2.name(), TEST_NAME_2);
        assertEq(nftContract2.symbol(), TEST_SYMBOL_2);
        assertEq(nftContract2.owner(), _creator2);

        // 배포 통계 확인
        uint256 totalDeployed = deployer.getTotalDeployedCount();
        assertEq(totalDeployed, 2);

        vm.stopPrank();
    }

    // @dev NFT 배포 실패 - 잘못된 파라미터 (빈 이름)
    function test_DeployFncyNFTFailInvalidName() public {
        vm.startPrank(_creator1);

        vm.expectPartialRevert(FncyNFTDeployer.InvalidParameter.selector);
        deployer.deployFncyNFT(
            "", // 빈 이름
            TEST_SYMBOL_1,
            TEST_BASE_URI_1,
            address(0),
            _creator1
        );

        vm.stopPrank();
    }

    // @dev NFT 배포 실패 - 잘못된 파라미터 (빈 심볼)
    function test_DeployFncyNFTFailInvalidSymbol() public {
        vm.startPrank(_creator1);

        vm.expectPartialRevert(FncyNFTDeployer.InvalidParameter.selector);
        deployer.deployFncyNFT(
            TEST_NAME_1,
            "", // 빈 심볼
            TEST_BASE_URI_1,
            address(0),
            _creator1
        );

        vm.stopPrank();
    }

    // ==========================================
    // 배포된 NFT 기능 테스트
    // ==========================================

    // @dev 배포된 NFT로 발행/소각 테스트
    function test_DeployedNFTMintAndBurn() public {
        // NFT 배포
        vm.startPrank(_creator1);
        (, address proxy, ) = deployer.deployFncyNFT(
            TEST_NAME_1,
            TEST_SYMBOL_1,
            TEST_BASE_URI_1,
            address(0),
            _creator1
        );

        FncyNFT nftContract = FncyNFT(proxy);

        // Minter 권한 추가
        nftContract.addMinter(_creator1);

        // NFT 발행
        uint256 tokenId = 1;
        nftContract.mint(_user1, tokenId, "metadata/1.json");

        // 발행 확인
        address owner = nftContract.ownerOf(tokenId);
        assertEq(owner, _user1);

        // NFT 소각
        nftContract.burn(tokenId);

        // 소각 확인
        assertEq(nftContract.getTotalBurned(), 1);

        vm.stopPrank();
    }

    // ==========================================
    // 다중 배포 테스트
    // ==========================================

    // @dev 다중 배포자가 각각 NFT 배포
    function test_MultipleCreatorsDeployment() public {
        // Creator1이 첫 번째 NFT 배포
        vm.startPrank(_creator1);
        (address proxyAdmin1, address proxy1, ) = deployer.deployFncyNFT(
            TEST_NAME_1,
            TEST_SYMBOL_1,
            TEST_BASE_URI_1,
            address(0),
            _creator1
        );
        vm.stopPrank();

        // Creator2가 두 번째 NFT 배포
        vm.startPrank(_creator2);
        (address proxyAdmin2, address proxy2, ) = deployer.deployFncyNFT(
            TEST_NAME_2,
            TEST_SYMBOL_2,
            TEST_BASE_URI_2,
            address(0),
            _creator2
        );
        vm.stopPrank();

        // 전체 배포 통계 확인
        uint256 totalDeployed = deployer.getTotalDeployedCount();
        assertEq(totalDeployed, 2);

        // 각 배포자별 컨트랙트 확인
        address[] memory creator1Contracts = deployer.getContractsByCreator(_creator1);
        address[] memory creator2Contracts = deployer.getContractsByCreator(_creator2);

        assertEq(creator1Contracts.length, 1);
        assertEq(creator2Contracts.length, 1);
        assertEq(creator1Contracts[0], proxy1);
        assertEq(creator2Contracts[0], proxy2);

        // 서로 다른 ProxyAdmin 사용 확인
        assertTrue(proxyAdmin1 != proxyAdmin2);
    }

    // @dev 동일 배포자가 여러 NFT 배포 (ProxyAdmin 재사용)
    function test_SameCreatorMultipleDeployments() public {
        vm.startPrank(_creator1);

        // 첫 번째 NFT 배포
        (address proxyAdmin1, address proxy1, ) = deployer.deployFncyNFT(
            TEST_NAME_1,
            TEST_SYMBOL_1,
            TEST_BASE_URI_1,
            address(0),
            _creator1
        );

        // 두 번째 NFT 배포 (동일한 ProxyAdmin 재사용)
        (address proxyAdmin2, address proxy2, ) = deployer.deployFncyNFT(
            TEST_NAME_2,
            TEST_SYMBOL_2,
            TEST_BASE_URI_2,
            proxyAdmin1, // 기존 ProxyAdmin 재사용
            _creator1
        );

        // 검증
        assertEq(proxyAdmin1, proxyAdmin2); // 동일한 ProxyAdmin
        assertTrue(proxy1 != proxy2); // 다른 프록시

        // 배포자 컨트랙트 목록 확인
        address[] memory creator1Contracts = deployer.getContractsByCreator(_creator1);
        assertEq(creator1Contracts.length, 2);
        assertEq(creator1Contracts[0], proxy1);
        assertEq(creator1Contracts[1], proxy2);

        // 두 NFT 모두 동일한 소유자
        FncyNFT nft1 = FncyNFT(proxy1);
        FncyNFT nft2 = FncyNFT(proxy2);
        assertEq(nft1.owner(), _creator1);
        assertEq(nft2.owner(), _creator1);

        vm.stopPrank();
    }

    // ==========================================
    // 배포 정보 조회 테스트
    // ==========================================

    // @dev 배포 정보 조회 - Success
    function test_GetContractInfo() public {
        // NFT 배포
        vm.startPrank(_creator1);
        (, address proxy, ) = deployer.deployFncyNFT(
            TEST_NAME_1,
            TEST_SYMBOL_1,
            TEST_BASE_URI_1,
            address(0),
            _creator1
        );
        vm.stopPrank();

        // 배포 정보 조회
        FncyNFTDeployer.DeployedContract memory info = deployer.getContractInfo(proxy);

        // 검증
        assertTrue(info.proxyAdmin != address(0));
        assertEq(info.proxy, proxy);
        assertTrue(info.implementation != address(0));
        assertEq(info.creator, _creator1);
        assertEq(info.name, TEST_NAME_1);
        assertEq(info.symbol, TEST_SYMBOL_1);
        assertTrue(info.deployedAt > 0);
    }

    // @dev 인덱스로 배포 정보 조회
    function test_GetDeployedContract() public {
        // 두 개의 NFT 배포
        vm.startPrank(_creator1);
        (, address proxy1, ) = deployer.deployFncyNFT(
            TEST_NAME_1,
            TEST_SYMBOL_1,
            TEST_BASE_URI_1,
            address(0),
            _creator1
        );
        vm.stopPrank();

        vm.startPrank(_creator2);
        (, address proxy2, ) = deployer.deployFncyNFT(
            TEST_NAME_2,
            TEST_SYMBOL_2,
            TEST_BASE_URI_2,
            address(0),
            _creator2
        );
        vm.stopPrank();

        // 첫 번째 배포 정보 조회
        FncyNFTDeployer.DeployedContract memory info1 = deployer.getDeployedContract(0);
        assertEq(info1.proxy, proxy1);
        assertEq(info1.creator, _creator1);

        // 두 번째 배포 정보 조회
        FncyNFTDeployer.DeployedContract memory info2 = deployer.getDeployedContract(1);
        assertEq(info2.proxy, proxy2);
        assertEq(info2.creator, _creator2);
    }

    // @dev 인덱스 조회 실패 - 잘못된 인덱스
    function test_GetDeployedContractFailInvalidIndex() public {
        vm.expectPartialRevert(FncyNFTDeployer.InvalidParameter.selector);
        deployer.getDeployedContract(0); // 아직 배포된 컨트랙트 없음
    }

    // ==========================================
    // 페이지네이션 테스트
    // ==========================================

    // @dev 최신 배포 목록 조회 (페이지네이션)
    function test_GetRecentDeployments() public {
        // 5개의 NFT 배포
        address[] memory proxies = new address[](5);

        for (uint256 i = 0; i < 5; i++) {
            vm.startPrank(_creator1);
            (, address proxy, ) = deployer.deployFncyNFT(
                string(abi.encodePacked("NFT Collection ", vm.toString(i + 1))),
                string(abi.encodePacked("NFT", vm.toString(i + 1))),
                TEST_BASE_URI_1,
                address(0),
                _creator1
            );
            proxies[i] = proxy;
            vm.stopPrank();
        }

        // 첫 번째 페이지 조회 (최신 3개)
        FncyNFTDeployer.DeployedContract[] memory recent = deployer.getRecentDeployments(0, 3);
        assertEq(recent.length, 3);

        // 최신순으로 반환되는지 확인 (역순)
        assertEq(recent[0].proxy, proxies[4]); // 가장 최신
        assertEq(recent[1].proxy, proxies[3]);
        assertEq(recent[2].proxy, proxies[2]);

        // 두 번째 페이지 조회
        FncyNFTDeployer.DeployedContract[] memory remaining = deployer.getRecentDeployments(3, 3);
        assertEq(remaining.length, 2); // 남은 2개만
        assertEq(remaining[0].proxy, proxies[1]);
        assertEq(remaining[1].proxy, proxies[0]); // 가장 오래된 것
    }

    // @dev 빈 페이지네이션 결과
    function test_GetRecentDeploymentsEmpty() public {
        // 배포된 컨트랙트가 없는 상태에서 조회
        FncyNFTDeployer.DeployedContract[] memory empty = deployer.getRecentDeployments(0, 10);
        assertEq(empty.length, 0);

        // 범위를 벗어난 오프셋
        vm.startPrank(_creator1);
        deployer.deployFncyNFT(TEST_NAME_1, TEST_SYMBOL_1, TEST_BASE_URI_1, address(0), _creator1);
        vm.stopPrank();

        FncyNFTDeployer.DeployedContract[] memory outOfRange = deployer.getRecentDeployments(10, 5);
        assertEq(outOfRange.length, 0);
    }

    // ==========================================
    // 배포자 통계 테스트
    // ==========================================

    // @dev 배포자 통계 조회
    function test_GetCreatorStats() public {
        vm.startPrank(_creator1);

        // 첫 번째 배포
        uint256 deployTime1 = block.timestamp;
        deployer.deployFncyNFT(TEST_NAME_1, TEST_SYMBOL_1, TEST_BASE_URI_1, address(0), _creator1);

        // 시간 진행
        vm.warp(block.timestamp + 3600); // 1시간 후

        // 두 번째 배포
        uint256 deployTime2 = block.timestamp;
        deployer.deployFncyNFT(TEST_NAME_2, TEST_SYMBOL_2, TEST_BASE_URI_2, address(0), _creator1);

        vm.stopPrank();

        // 통계 조회
        (uint256 totalCount, uint256 firstDeployedAt, uint256 lastDeployedAt) = deployer.getCreatorStats(_creator1);

        // 검증
        assertEq(totalCount, 2);
        assertEq(firstDeployedAt, deployTime1);
        assertEq(lastDeployedAt, deployTime2);
    }

    // @dev 배포 이력이 없는 배포자 통계
    function test_GetCreatorStatsEmpty() public {
        (uint256 totalCount, uint256 firstDeployedAt, uint256 lastDeployedAt) = deployer.getCreatorStats(_user1);

        assertEq(totalCount, 0);
        assertEq(firstDeployedAt, 0);
        assertEq(lastDeployedAt, 0);
    }

    // ==========================================
    // 소유권 및 권한 테스트
    // ==========================================

    // @dev newOwner 지정하지 않은 경우 (msg.sender가 소유자)
    function test_DeployFncyNFTDefaultOwner() public {
        vm.startPrank(_creator1);

        (address proxyAdmin, address proxy, ) = deployer.deployFncyNFT(
            TEST_NAME_1,
            TEST_SYMBOL_1,
            TEST_BASE_URI_1,
            address(0),
            address(0) // newOwner를 지정하지 않음
        );

        // msg.sender(_creator1)가 소유자가 되어야 함
        FncyNFT nftContract = FncyNFT(proxy);
        ProxyAdmin adminContract = ProxyAdmin(proxyAdmin);

        assertEq(nftContract.owner(), _creator1);
        assertEq(adminContract.owner(), _creator1);

        vm.stopPrank();
    }

    // @dev 다른 주소로 소유권 이전하여 배포
    function test_DeployFncyNFTWithDifferentOwner() public {
        vm.startPrank(_creator1);

        (address proxyAdmin, address proxy, ) = deployer.deployFncyNFT(
            TEST_NAME_1,
            TEST_SYMBOL_1,
            TEST_BASE_URI_1,
            address(0),
            _foundation // 재단이 소유자
        );

        // 재단이 소유자가 되어야 함
        FncyNFT nftContract = FncyNFT(proxy);
        ProxyAdmin adminContract = ProxyAdmin(proxyAdmin);

        assertEq(nftContract.owner(), _foundation);
        assertEq(adminContract.owner(), _foundation);

        // 하지만 배포자는 여전히 _creator1
        FncyNFTDeployer.DeployedContract memory info = deployer.getContractInfo(proxy);
        assertEq(info.creator, _creator1);

        vm.stopPrank();
    }

    // ==========================================
    // 대량 배포 테스트
    // ==========================================

    // @dev 대량 배포 시뮬레이션
    function test_LargeScaleDeployment() public {
        uint256 deployCount = 10;
        address[] memory proxies = new address[](deployCount);

        // 10개의 NFT 컨트랙트 배포
        for (uint256 i = 0; i < deployCount; i++) {
            vm.startPrank(_creator1);
            (, address proxy, ) = deployer.deployFncyNFT(
                string(abi.encodePacked("Collection ", vm.toString(i + 1))),
                string(abi.encodePacked("COL", vm.toString(i + 1))),
                TEST_BASE_URI_1,
                address(0),
                _creator1
            );
            proxies[i] = proxy;
            vm.stopPrank();
        }

        // 통계 확인
        uint256 totalDeployed = deployer.getTotalDeployedCount();
        assertEq(totalDeployed, deployCount);

        address[] memory creator1Contracts = deployer.getContractsByCreator(_creator1);
        assertEq(creator1Contracts.length, deployCount);

        // 각 컨트랙트가 정상 작동하는지 확인
        for (uint256 i = 0; i < deployCount; i++) {
            FncyNFT nft = FncyNFT(proxies[i]);
            assertEq(nft.owner(), _creator1);
        }
    }

    // ==========================================
    // 통합 테스트
    // ==========================================

    // @dev 배포 → 발행 → 전송 → 소각 통합 테스트
    function test_DeployAndFullNFTLifecycle() public {
        // 1. NFT 배포
        vm.startPrank(_creator1);
        (, address proxy, ) = deployer.deployFncyNFT(
            TEST_NAME_1,
            TEST_SYMBOL_1,
            TEST_BASE_URI_1,
            address(0),
            _creator1
        );

        FncyNFT nftContract = FncyNFT(proxy);

        // 2. Minter 권한 추가
        nftContract.addMinter(_creator1);

        // 3. NFT 발행
        uint256 tokenId = 1;
        nftContract.mint(_user1, tokenId, "metadata/1.json");
        assertEq(nftContract.ownerOf(tokenId), _user1);

        vm.stopPrank();

        // 4. NFT 전송
        vm.startPrank(_user1);
        nftContract.transferFrom(_user1, _user2, tokenId);
        assertEq(nftContract.ownerOf(tokenId), _user2);
        vm.stopPrank();

        // 5. NFT 소각
        vm.startPrank(_creator1);
        nftContract.burn(tokenId);
        assertEq(nftContract.getTotalBurned(), 1);

        vm.stopPrank();
    }

    // ==========================================
    // 배포 이벤트 테스트
    // ==========================================

    // @dev 배포 이벤트 발생 확인
    function test_DeploymentEvents() public {
        vm.startPrank(_creator1);

        // 이벤트 기대값 설정
        vm.expectEmit(true, true, true, false);

        // NFT 배포 (이벤트 발생)
        deployer.deployFncyNFT(
            TEST_NAME_1,
            TEST_SYMBOL_1,
            TEST_BASE_URI_1,
            address(0),
            _creator1
        );

        vm.stopPrank();
    }

    // ==========================================
    // Deployer 관리 기능 테스트
    // ==========================================

    // @dev 수수료 인출 테스트 (향후 기능)
    function test_WithdrawFeesEmpty() public {
        vm.startPrank(_foundation);

        // 잔액이 없는 상태에서 인출 시도 (문제없이 실행되어야 함)
        deployer.withdrawFees(payable(_foundation));

        vm.stopPrank();
    }

    // @dev 수수료 인출 실패 - 오너가 아님
    function test_WithdrawFeesFailNotOwner() public {
        vm.startPrank(_developer);
        vm.expectRevert("Ownable: caller is not the owner");
        deployer.withdrawFees(payable(_developer));
        vm.stopPrank();
    }

    // @dev 수수료 인출 실패 - 잘못된 주소
    function test_WithdrawFeesFailInvalidAddress() public {
        vm.startPrank(_foundation);
        vm.expectPartialRevert(FncyNFTDeployer.InvalidParameter.selector);
        deployer.withdrawFees(payable(address(0)));
        vm.stopPrank();
    }

    // ==========================================
    // 헬퍼 함수
    // ==========================================

    function _deployNFT(
        address creator,
        string memory name,
        string memory symbol,
        string memory baseURI,
        address proxyAdmin,
        address owner
    ) internal returns (address proxy) {
        vm.startPrank(creator);
        (, proxy, ) = deployer.deployFncyNFT(name, symbol, baseURI, proxyAdmin, owner);
        vm.stopPrank();
        return proxy;
    }
}