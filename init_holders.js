const web3 = require("web3")
const init_holders = [
  {
    address: "0xE65FDc72F2CD178F04Db194f3AB89dA6FafE132A",
    balance: web3.utils.toBN("100000000000000000000000000000").toString("hex")
  },
  {
    address: "0xE52497FCA47cA80F6eAa161A80c0FAd247DDb457",
    balance: web3.utils.toBN("10000000000000000000000000000").toString("hex")
  }
];


exports = module.exports = init_holders
