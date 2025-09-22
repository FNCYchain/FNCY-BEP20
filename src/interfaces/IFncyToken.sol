pragma solidity ^0.8.14;

import {IERC20Upgradeable} from "../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

interface IFncyToken is IERC20Upgradeable {
    /*
    ########################
    ###      Error       ###
    ########################
    */
    // @dev Invalid Parameter
    error InvalidParameter();
    // @dev Already Minter Address
    error AlreadyMinterAddress();
    // @dev Not Exists Minter
    error NotExistsMinterAddress();
    // @dev Minting 시 MaxSupply 관리
    error MaxSupplyExceeded(uint256 requested, uint256 available);
    // @dev Minter 권한 없음.
    error UnauthorizedMinting(address minter);
    // @dev 물량 소각 시 밸런스 부족
    error InsufficientBalance(uint256 balance, uint256 amount);
    // @dev 물량 소각 시 유통량 부족
    error InsufficientCirculating(uint256 circulating, uint256 amount);

    /*
    ########################
    ###      Event       ###
    ########################
    */
    event AddMinter(address minter);
    event RemoveMinter(address minter);
    event Mint(address account, uint256 amount);
    event Burn(address account, uint256 amount);
    event Lock(address from, address to, uint256 amount);
    event SoftBurn(address from, address to, uint256 amount);
    event RescueTokens(address to, uint256 amount);

    /**
     * @dev 해당 토큰을 Minting 할 수 있는 권한을 가진 모든 주소를 조회합니다.
     */
    function getMinters() external view returns (address[] memory);
    /**
     * @dev 총 소각량 조회
     */
    function getTotalBurned() external view returns(uint256);
    /**
     * @dev 소각량 제외 유통량 조회
     */
    function getCirculating() external view returns(uint256);
    /**
     * @dev 해당 토큰을 Minting 할 수 있는 Minter 권한을 가지고 있는지 조회합니다.
     * @param minter Minter 권한을 가지고 있는지 조회 할 주소
     */
    function isMinter(address minter) external view returns (bool);
    /**
     * @dev 해당 토큰을 Minting 할 수 있는 Minter 권한을 부여합니다.
     * @notice 대상 주소가 Minter 권한을 가지고 있지 않아야 합니다.
     * @param minter Minter 권한을 부여할 주소
     */
    function addMinter(address minter) external;
    /**
     * @dev 해당 토큰을 Minting 할 수 있는 Minter 권한을 제거합니다.
     * @notice 대상 주소가 Minter 권한을 가지고 있어야합니다.
     * @param minter Minter 권한을 제거할 주소
     */
    function removeMinter(address minter) external;
    /**
     * @dev Token Minting
     * @notice Minter 권한을 가진 주소만이 실행 가능, Total Supply 가 증가됨.
     * MAX_SUPPLY 를 넘길 수 없음.
     * @param account 민팅 대상 주소
     * @param amount 민팅 토큰 수량
     */
    function mint(address account, uint256 amount) external;
    /**
     * @dev Token Burn
     * @notice Minter 권한을 가진 주소만이 실행 가능, Total Supply 가 감소됨.
     * @param amount 소각 토큰 수량
     */
    function burn(uint256 amount) external;
    /**
     * @dev Token Lock
     * @notice 토큰을 가지고 있는 유저가 실행 가능함. Contract 에 Lock
     * @param amount Lock Token Amount
     */
    function lock(uint256 amount) external;
    /**
     * @dev Token Soft Burn ( Token Lock -> Dead)
     * @notice 어드민(오너)만 실행가능함. 토큰 컨트랙트에 Lock 되어 있는 물량을 Dead 또는 Zero로 전송.
     * @notice 위 burn 기능과는 상이함. 기록을 위해 Zero로 실제로 토큰을 보냄
     * @param amount 소각 토큰 수량
     */
    function softBurnWithAdmin(uint256 amount) external;
    /**
     * @dev 민팅 가능 여부 ( 실시간 사용 시 )
     * @notice 초기 배포 시 FNCY 종료 스냅샷 블록과 배포 시점 블록을 이용하여 기존 FNCY 기준 민팅 블록이 남았는지.
     */
    function isMintingAllowed() external view returns (bool);
    /**
     * @dev Minting 가능 토큰 개수 조회
     * @notice 초기 배포 후 20억개를 바로 발행하지 않는 케이스로 진행할 경우 해당 함수를 통해 몇 개의 토큰을 발행할 수 있는지 체크
     */
    function remainingMintableSupply() external view returns (uint256);
    /**
     * @dev Minting 가능 토큰 개수 조회
     * @param amount 컨트랙트에서 출금할 양
     */
    function rescueTokens(uint256 amount) external;
}
