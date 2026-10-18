// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;
interface IQuantumComputeRental {
    function bookGpuCluster(bytes32 workloadHash) external payable returns (uint256);
    function increaseBookingTime(uint256 taskId) external payable;
}
