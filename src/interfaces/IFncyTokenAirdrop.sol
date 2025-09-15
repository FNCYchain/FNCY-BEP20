pragma solidity ^0.8.14;

interface IFncyTokenAirdrop {
    /*
    ########################
    ###      Error       ###
    ########################
    */
    // @dev Invalid Parameter
    error InvalidParameter();
    // @dev 대상 토큰이 등록되지 않음.
    error TokenNotSet();
    // @dev 에어드랍 권한 없음
    error UnauthorizedAirdropExecute(address minter);
    // @dev 이미 에어드랍 권한이 존재함
    error AlreadyAirdropExecutePerm(address executor);
    // @dev 에어드랍 권한이 존재하지 않음.
    error NotExistsAirdropExecutor(address executor);
    // @dev 에어드랍 물량 초과 ( 논의 필요 [보유 수 만큼 OK 또는 관리 물량만])
    error MaxAirdropLimitExceeded();
    // @dev 배치 크기가 너무 큼
    error BatchSizeTooLarge(uint256 requested, uint256 maxSize);
    // @dev Contract Pool 에어드랍 시 밸런스 부족
    error InsufficientContractBalance(uint256 balance, uint256 amount);
    // @dev Contract Pool 에 오너가 입금 시 Approve 되어 있지 않을 시
    error InsufficientAllowance(uint256 allowance, uint256 amount);

    /*
    ########################
    ###      Event       ###
    ########################
    */
    event ChangeTargetToken(address be, address af);
    event AddAirdropExecutor(address executor);
    event RemoveAirdropExecutor(address executor);
    event AirdropLimitChanged(uint256 oldLimit, uint256 newLimit);
    event TokenRescued(address token, address to, uint256 amount);
    event TokenAirdropped(address to, uint256 amount);
    event PoolDeposited(address from, uint256 amount);
    event PoolWithdrawn(address to, uint256 amount);

    /**
     * @dev 에어드랍 상태 조회
     * @return totalExecuted 총 에어드랍 실행 횟수
     * @return totalRecipients 총 고유 수신자 수
     * @return totalAmount 총 에어드랍 금액
     */
    function getAirdropStatus() external view returns (uint256 totalExecuted, uint256 totalRecipients, uint256 totalAmount);
    /**
     * @dev 현재까지 진행한 Airdrop 총액
     * @return 총 에어드랍 금액
     */
    function getTotalAirdropAmount() external view returns(uint256);
    /**
     * @dev 현재 에어드랍 제한량 조회
     * @return 에어드랍 제한량
     */
    function getAirdropLimit() external view returns(uint256);
    /**
     * @dev 남은 에어드랍 가능량 조회
     * @return 남은 에어드랍 가능량
     */
    function getRemainingAirdropAmount() external view returns(uint256);
    /**
     * @dev 에어드랍 제한량 설정
     * @param limit 새 제한량
     */
    function setAirdropLimit(uint256 limit) external;
    /**
     * @dev 토큰 주소 변경 (긴급 상황용)
     * @param newToken 새 토큰 주소
     */
    function changeTargetToken(address newToken) external;
    /**
     * @dev Airdrop Execute 권한 여부 조회
     * @param executor Airdrop 을 Execute 권한을 가지고 있는지 조회 할 주소
     */
    function isExecutor(address executor) external view returns(bool);
    /**
     * @dev 등록된 모든 Executor 조회
     * @return 모든 실행자 주소 배열
     */
    function getExecutors() external view returns(address[] memory);
    /**
     * @dev Airdrop Execute 권한 부여
     * @notice 대상 주소가 Airdrop 권한을 가지고 있지 않아야함.
     * @param executor Airdrop 을 Execute 권한을 부여할 주소
     */
    function addAirdropExecutor(address executor) external;
    /**
     * @dev Airdrop Execute 권한 회수
     * @notice 대상 주소가 Airdrop 권한을 가지고 있어야함.
     * @param executor Airdrop 을 Execute 권한을 회수할 주소
     */
    function removeAirdropExecutor(address executor) external;
    /**
     * @dev Token Airdrop
     * @notice Executor 권한을 가진 주소가 실행해야함.
     * @param from Airdrop 을 위임받은 출금 주소
     * @param to Airdrop 을 통해 물량을 전달 받을 주소
     * @param amount Airdrop 을 통해 전달 받을 물량
     */
    function airdrop(address from, address to, uint256 amount) external;
    /**
     * @dev 배치 에어드랍 실행
     * @param froms 에어드랍 출금 주소 배열
     * @param recipients 수신자 배열
     * @param amounts 수량 배열
     */
    function batchAirdrop(address[] calldata froms, address[] calldata recipients, uint256[] calldata amounts) external;
    /**
     * @dev 주소별 에어드랍 수령량 조회
     * @param recipient 조회할 주소
     * @return 수령한 에어드랍 총량
     */
    function getReceivedAmount(address recipient) external view returns(uint256);
    /**
     * @dev 컨트랙트가 보유한 토큰 잔액 조회
     * @notice 편의성을 위해 생성한 함수
     * @return 컨트랙트의 토큰 잔액
     */
    function getContractTokenBalance() external view returns(uint256);
    /**
     * @dev 오너가 컨트랙트에 토큰 입금 (에어드랍 풀 충전용)
     * @notice 호출 전에 반드시 approve(airdropContract, amount) 필요
     * @notice 단순 토큰 입금해도 무방하나, 기록을 위해 생성함.
     * @param amount 입금할 토큰 수량
     */
    function depositToPool(uint256 amount) external;
    /**
     * @dev 오너가 컨트랙트에서 토큰 출금 (미사용 토큰 회수용)
     * @param amount 출금할 토큰 수량
     */
    function withdrawFromPool(uint256 amount) external;
    /**
     * @dev 컨트랙트가 보유한 토큰으로 에어드랍 실행
     * @param to 에어드랍 수신자
     * @param amount 에어드랍 수량
     */
    function airdropFromPool(address to, uint256 amount) external;
    /**
     * @dev 컨트랙트가 보유한 토큰으로 배치 에어드랍 실행
     * @param recipients 수신자 배열
     * @param amounts 수량 배열
     */
    function batchAirdropFromPool(address[] calldata recipients, uint256[] calldata amounts) external;
}