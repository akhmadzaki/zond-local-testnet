const config = require("./config.json")
const { Web3 } = require('@theqrl/web3')
const web3 = new Web3(new Web3.providers.HttpProvider(config.provider))

const acc = web3.zond.accounts.seedToAccount(config.hexseed)
web3.zond.wallet?.add(config.hexseed)
web3.zond.transactionConfirmationBlocks = config.tx_required_confirmations

const transferMyToken = async () => {
    const estimatedGas = await web3.zond.estimateGas({"from": acc.address, to: config.to, value: web3.utils.toWei(config.amount, "ether")})
    console.log(estimatedGas)
    const txObj = {type: '0x2', gas: estimatedGas, from: acc.address, data: "0x", to: config.to, value: web3.utils.toWei(config.amount, "ether")}
    await web3.zond.sendTransaction(txObj, undefined, { checkRevertBeforeSending: true })
    .on('confirmation', console.log)
    .on('receipt', console.log)
    .on('error', console.error)
}

transferMyToken()