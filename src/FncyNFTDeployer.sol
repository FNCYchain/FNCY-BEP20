// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {ProxyAdmin} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {FncyNFT} from "./FncyNFT.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title FncyNFTDeployer
 * @dev FNCY NFT 컨트랙트를 업그레이더블 프록시 패턴으로 배포하는 팩토리 컨트랙트
 */
contract FncyNFTDeployer is Ownable {
    /*
    ########################
    ###      Events      ###
    ########################
    */
    event NFTContractDeployed(
        address indexed creator,
        address indexed proxyAdmin,
        address indexed proxy,
        address implementation,
        string name,
        string symbol,
        string baseURI
    );

    event OwnershipTransferred(
        address indexed proxy,
        address indexed previousOwner,
        address indexed newOwner
    );

    /*
    ########################
    ###      Errors      ###
    ########################
    */
    error InvalidParameter();
    error DeploymentFailed();

    /*
    ########################
    ###      Storage     ###
    ########################
    */

    // 배포된 NFT 컨트랙트들 추적
    struct DeployedContract {
        address proxyAdmin;
        address proxy;
        address implementation;
        address creator;
        string name;
        string symbol;
        uint256 deployedAt;
    }

    // 배포된 컨트랙트 목록
    DeployedContract[] public deployedContracts;

    // 배포자별 컨트랙트 매핑
    mapping(address => address[]) public creatorToContracts;

    // 프록시 주소로 배포 정보 조회
    mapping(address => DeployedContract) public contractInfo;

    constructor() {}

    /**
     * @dev FNCY NFT 컨트랙트 배포 (기본 설정)
     * @param name NFT 컬렉션 이름
     * @param symbol NFT 심볼
     * @param baseURI 베이스 메타데이터 URI
     * @param newOwner 배포 후 소유권을 이전받을 주소 (address(0)이면 msg.sender)
     * @return proxyAdmin ProxyAdmin 주소
     * @return proxy 프록시 주소 (실제 NFT 컨트랙트)
     * @return implementation 구현체 주소
     */
    function deployFncyNFT(
        string memory name,
        string memory symbol,
        string memory baseURI,
        address ordProxyAdmin, // 이미 있는 proxy admin 사용할 시 주소 입력
        address newOwner
    ) public returns (
        address proxyAdmin,
        address proxy,
        address implementation
    ) {
        if (bytes(name).length == 0 || bytes(symbol).length == 0) revert InvalidParameter();

        address targetOwner = newOwner == address(0) ? msg.sender : newOwner;

        // 1. Proxy Admin 배포 (external call이 없는 작업)
        if (ordProxyAdmin == address(0)) {
            proxyAdmin = address(new ProxyAdmin());
        } else {
            proxyAdmin = ordProxyAdmin;
        }

        // 2. NFT 구현체 배포 (external call이 없는 작업)
        implementation = address(new FncyNFT());

        // 3. Transparent Proxy 배포 (external call이 없는 작업)
        proxy = address(new TransparentUpgradeableProxy(
            implementation,
            proxyAdmin,
            abi.encodeWithSignature(
                "initialize(string,string,string)",
                name,
                symbol,
                baseURI
            )
        ));

        // 4. State changes before external calls (CEI pattern)
        _recordDeployment(proxyAdmin, proxy, implementation, msg.sender, name, symbol);

        // 5. External calls last
        if (ordProxyAdmin == address(0)) {
            ProxyAdmin(proxyAdmin).transferOwnership(targetOwner);
        }
        FncyNFT(proxy).transferOwnership(targetOwner);

        emit NFTContractDeployed(
            msg.sender,
            proxyAdmin,
            proxy,
            implementation,
            name,
            symbol,
            baseURI
        );

        return (proxyAdmin, proxy, implementation);
    }

    /**
     * @dev 특정 배포자가 배포한 컨트랙트 목록 조회
     * @param creator 배포자 주소
     * @return contracts 배포한 컨트랙트 주소 배열
     */
    function getContractsByCreator(address creator) external view returns (address[] memory contracts) {
        return creatorToContracts[creator];
    }

    /**
     * @dev 전체 배포된 컨트랙트 수량 조회
     * @return count 배포된 컨트랙트 총 개수
     */
    function getTotalDeployedCount() external view returns (uint256 count) {
        return deployedContracts.length;
    }

    /**
     * @dev 특정 인덱스의 배포 정보 조회
     * @param index 조회할 인덱스
     * @return deployedContract 배포 정보
     */
    function getDeployedContract(uint256 index) external view returns (DeployedContract memory deployedContract) {
        if (index >= deployedContracts.length) revert InvalidParameter();
        return deployedContracts[index];
    }

    /**
     * @dev 프록시 주소로 배포 정보 조회
     * @param proxy 프록시 주소
     * @return deployedContract 배포 정보
     */
    function getContractInfo(address proxy) external view returns (DeployedContract memory deployedContract) {
        return contractInfo[proxy];
    }

    /**
     * @dev 최신 배포된 컨트랙트들 조회 (페이지네이션)
     * @param offset 시작 오프셋
     * @param limit 조회할 개수
     * @return contracts 배포 정보 배열
     */
    function getRecentDeployments(uint256 offset, uint256 limit) external view returns (DeployedContract[] memory contracts) {
        uint256 total = deployedContracts.length;
        if (offset >= total) {
            return new DeployedContract[](0);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }

        uint256 size = end - offset;
        contracts = new DeployedContract[](size);

        // 최신순으로 반환 (역순)
        for (uint256 i = 0; i < size; i++) {
            contracts[i] = deployedContracts[total - 1 - offset - i];
        }

        return contracts;
    }

    /**
     * @dev 배포자별 통계 조회
     * @param creator 배포자 주소
     * @return totalCount 총 배포 개수
     * @return firstDeployedAt 첫 배포 시간
     * @return lastDeployedAt 마지막 배포 시간
     */
    function getCreatorStats(address creator) external view returns (
        uint256 totalCount,
        uint256 firstDeployedAt,
        uint256 lastDeployedAt
    ) {
        address[] memory contracts = creatorToContracts[creator];
        totalCount = contracts.length;

        if (totalCount == 0) {
            return (0, 0, 0);
        }

        // 첫 번째와 마지막 배포 시간 찾기
        firstDeployedAt = type(uint256).max;
        lastDeployedAt = 0;

        for (uint256 i = 0; i < contracts.length; i++) {
            uint256 deployedAt = contractInfo[contracts[i]].deployedAt;
            if (deployedAt < firstDeployedAt) {
                firstDeployedAt = deployedAt;
            }
            if (deployedAt > lastDeployedAt) {
                lastDeployedAt = deployedAt;
            }
        }

        return (totalCount, firstDeployedAt, lastDeployedAt);
    }

    /**
     * @dev 배포 수수료 설정 (향후 확장용)
     * @param fee 새로운 수수료 (wei)
     */
    function setDeploymentFee(uint256 fee) external onlyOwner {
        // 향후 배포 수수료 기능 구현 시 사용
    }

    /**
     * @dev 컨트랙트에서 수수료 인출 (향후 확장용)
     * @param to 인출받을 주소
     */
    function withdrawFees(address payable to) external onlyOwner {
        if (to == address(0)) revert InvalidParameter();

        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = to.call{value: balance}("");
            if (!success) revert DeploymentFailed();
        }
    }

    /**
     * @dev 배포 정보 기록
     */
    function _recordDeployment(
        address proxyAdmin,
        address proxy,
        address implementation,
        address creator,
        string memory name,
        string memory symbol
    ) internal {
        DeployedContract memory newContract = DeployedContract({
            proxyAdmin: proxyAdmin,
            proxy: proxy,
            implementation: implementation,
            creator: creator,
            name: name,
            symbol: symbol,
            deployedAt: block.timestamp
        });

        deployedContracts.push(newContract);
        creatorToContracts[creator].push(proxy);
        contractInfo[proxy] = newContract;
    }

    /**
     * @dev 이더 수신 가능 (향후 수수료 기능용)
     */
    receive() external payable {}
}