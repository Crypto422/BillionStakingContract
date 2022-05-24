const hre = require("hardhat");

// npx hardhat verify --network rinkeby 0x6719c3d7d181688400F53aa312d01A6e9AD6CFA1 "0xab1ea131FD1f9aF453A38fEA643c7e7946B5a144" "0x28D3d93f3223A2B80E32e37311D4cB7147DeC5Cd" 
async function main() {
    // const CashP = await hre.ethers.getContractFactory("CashP");
    // const cashp = await CashP.deploy();
    // await cashp.deployed();
    const Staking = await hre.ethers.getContractFactory("Staking");
    const staking = await Staking.deploy("0xA041546127237ad45354e1B98f4C13DeefE5a848", "0x4F499C43b8060FB794147B18cefec7D5Ad76107D");
    await staking.deployed();
    // console.log("Cashp deployed to:", cashp.address);
    console.log("Staking deployed to:", staking.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });