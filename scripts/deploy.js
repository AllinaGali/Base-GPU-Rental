const hre = require("hardhat");
async function main() {
  const Rental = await hre.ethers.getContractFactory("QuantumComputeRental");
  const rental = await Rental.deploy();
  await rental.deployed();
  console.log("Compute Rental deployed to:", rental.address);
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
