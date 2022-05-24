require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");

require('dotenv').config();

const { MOONRIVER_API_URL,ETH_API_URL, PRIVATE_KEY, MOONRIVER_API,ETHSCAN_API } = process.env;

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
    const accounts = await hre.ethers.getSigners();

    for (const account of accounts) {
        console.log(account.address);
    }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    solidity: {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
    networks: {
        moonriver: {
            url: MOONRIVER_API_URL,
            accounts: [PRIVATE_KEY],
        },
        rinkeby: {
            url: ETH_API_URL,
            accounts: [PRIVATE_KEY],
        },
    },
    etherscan: {
        apiKey: MOONRIVER_API
    },
};