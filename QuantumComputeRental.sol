// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract QuantumComputeRental {
    enum TaskStatus { Open, Processing, Completed, Canceled }

    struct ComputeTask {
        address payable client;
        address payable provider;
        uint256 lockedWei;
        TaskStatus status;
        bytes32 workloadHash;
    }

    address payable public immutable networkAdmin;
    string public networkDescriptor;
    uint256 public platformFeeBps; // 250 = 2.5%
    uint256 public taskCounter;
    uint256 public accumulatedFees;
    bool public isNetworkHalted;

    mapping(address => bool) public verifiedProviders;
    mapping(uint256 => ComputeTask) public computeTasks;

    event TaskAccepted(uint256 indexed taskId, address indexed provider);
    event ClusterBooked(uint256 indexed taskId, address indexed client, uint256 amount);
    event BookingCanceled(uint256 indexed taskId, uint256 refund);
    event TreasuryDeposited(address indexed funder, uint256 amount);
    event ReservesEmptied(address indexed admin, uint256 amount);
    event TaskFinished(uint256 indexed taskId, uint256 payout);
    event FeesGathered(address indexed admin, uint256 amount);
    event NetworkHaltToggled(bool isHalted);
    event TimeIncreased(uint256 indexed taskId, uint256 addedAmount);
    event ClusterListed(address indexed provider, bytes32 specsHash);
    event ProviderRevoked(address indexed provider);
    event DescriptorUpdated(string newDescriptor);

    modifier onlyAdmin() {
        require(msg.sender == networkAdmin, "Quantum: Access denied");
        _;
    }

    modifier whenNotHalted() {
        require(!isNetworkHalted, "Quantum: Network halted");
        _;
    }

    constructor() {
        networkAdmin = payable(msg.sender);
        networkDescriptor = "Quantum Base GPU Compute Network v1";
        platformFeeBps = 250; // 2.5%
        isNetworkHalted = false;
        verifiedProviders[msg.sender] = true;
    }

    // 1. acceptComputeTask
    function acceptComputeTask(uint256 taskId) external whenNotHalted {
        ComputeTask storage t = computeTasks[taskId];
        require(taskId > 0 && taskId <= taskCounter, "Quantum: Invalid ID");
        require(verifiedProviders[msg.sender], "Quantum: Not a provider");
        require(t.status == TaskStatus.Open, "Quantum: Task not open");

        t.provider = payable(msg.sender);
        t.status = TaskStatus.Processing;
        emit TaskAccepted(taskId, msg.sender);
    }

    // 2. bookGpuCluster
    function bookGpuCluster(bytes32 workloadHash) external payable whenNotHalted returns (uint256) {
        require(msg.value > 0, "Quantum: Zero payment");

        taskCounter++;
        computeTasks[taskCounter] = ComputeTask({
            client: payable(msg.sender),
            provider: payable(address(0)),
            lockedWei: msg.value,
            status: TaskStatus.Open,
            workloadHash: workloadHash
        });

        emit ClusterBooked(taskCounter, msg.sender, msg.value);
        return taskCounter;
    }

    // 3. cancelClusterBooking
    function cancelClusterBooking(uint256 taskId) external {
        ComputeTask storage t = computeTasks[taskId];
        require(taskId > 0 && taskId <= taskCounter, "Quantum: Invalid ID");
        require(msg.sender == t.client || msg.sender == networkAdmin, "Quantum: Unauthorized");
        require(t.status == TaskStatus.Open, "Quantum: Cannot cancel now");

        t.status = TaskStatus.Canceled;
        uint256 refund = t.lockedWei;
        t.lockedWei = 0;

        if (refund > 0) {
            (bool sent, ) = t.client.call{value: refund}("");
            require(sent, "Quantum: Refund failed");
        }

        emit BookingCanceled(taskId, refund);
    }

    // 4. depositPlatformTreasury
    function depositPlatformTreasury() external payable whenNotHalted {
        require(msg.value > 0, "Quantum: Zero deposit");
        accumulatedFees += msg.value;
        emit TreasuryDeposited(msg.sender, msg.value);
    }

    // 5. emptyPlatformReserves
    function emptyPlatformReserves() external onlyAdmin {
        uint256 balance = address(this).balance;
        require(balance > 0, "Quantum: Zero balance");

        accumulatedFees = 0;
        (bool sent, ) = networkAdmin.call{value: balance}("");
        require(sent, "Quantum: Sweep failed");

        emit ReservesEmptied(networkAdmin, balance);
    }

    // 6. finishComputeTask
    function finishComputeTask(uint256 taskId) external {
        ComputeTask storage t = computeTasks[taskId];
        require(taskId > 0 && taskId <= taskCounter, "Quantum: Invalid ID");
        require(msg.sender == t.provider || msg.sender == networkAdmin, "Quantum: Unauthorized");
        require(t.status == TaskStatus.Processing, "Quantum: Not processing");

        t.status = TaskStatus.Completed;
        
        uint256 fee = (t.lockedWei * platformFeeBps) / 10000;
        uint256 payout = t.lockedWei - fee;
        
        accumulatedFees += fee;
        t.lockedWei = 0;

        if (payout > 0) {
            (bool sent, ) = t.provider.call{value: payout}("");
            require(sent, "Quantum: Payout failed");
        }

        emit TaskFinished(taskId, payout);
    }

    // 7. gatherPlatformFees
    function gatherPlatformFees() external onlyAdmin {
        uint256 amount = accumulatedFees;
        require(amount > 0, "Quantum: Zero fees");

        accumulatedFees = 0;
        (bool sent, ) = networkAdmin.call{value: amount}("");
        require(sent, "Quantum: Harvest failed");

        emit FeesGathered(networkAdmin, amount);
    }

    // 8. haltComputeNetwork
    function haltComputeNetwork(bool isHalted) external onlyAdmin {
        isNetworkHalted = isHalted;
        emit NetworkHaltToggled(isHalted);
    }

    // 9. increaseBookingTime
    function increaseBookingTime(uint256 taskId) external payable whenNotHalted {
        ComputeTask storage t = computeTasks[taskId];
        require(taskId > 0 && taskId <= taskCounter, "Quantum: Invalid ID");
        require(msg.sender == t.client, "Quantum: Not the client");
        require(t.status == TaskStatus.Open || t.status == TaskStatus.Processing, "Quantum: Cannot increase now");
        require(msg.value > 0, "Quantum: Zero payment");

        t.lockedWei += msg.value;
        emit TimeIncreased(taskId, msg.value);
    }

    // 10. listGpuCluster
    function listGpuCluster(bytes32 specsHash) external onlyAdmin {
        require(verifiedProviders[msg.sender], "Quantum: Not verified");
        emit ClusterListed(msg.sender, specsHash);
    }

    // 11. revokeProviderStatus
    function revokeProviderStatus(address provider) external onlyAdmin {
        require(verifiedProviders[provider], "Quantum: Not a provider");
        require(provider != msg.sender, "Quantum: Cannot revoke self");
        verifiedProviders[provider] = false;
        emit ProviderRevoked(provider);
    }

    // 12. updateNetworkDescriptor
    function updateNetworkDescriptor(string calldata newDescriptor) external onlyAdmin {
        require(bytes(newDescriptor).length > 0, "Quantum: Empty string");
        networkDescriptor = newDescriptor;
        emit DescriptorUpdated(newDescriptor);
    }
}