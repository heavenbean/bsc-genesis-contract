const web3 = require("web3")
const RLP = require('rlp');

// Configure
const validators = [
  {
    consensusAddr: "0xE65FDc72F2CD178F04Db194f3AB89dA6FafE132A",
    feeAddr: "0xE65FDc72F2CD178F04Db194f3AB89dA6FafE132A",
    bscFeeAddr: "0xE65FDc72F2CD178F04Db194f3AB89dA6FafE132A",
    votingPower: 0x0000000000002710
  },
  {
    consensusAddr: "0xE52497FCA47cA80F6eAa161A80c0FAd247DDb457",
    feeAddr: "0xE52497FCA47cA80F6eAa161A80c0FAd247DDb457",
    bscFeeAddr: "0xE52497FCA47cA80F6eAa161A80c0FAd247DDb457",
    votingPower: 0x0000000000002710
  },
];

// ===============  Do not edit below ====
function generateExtradata(validators) {
  let extraVanity =Buffer.alloc(32);
  let validatorsBytes = extraDataSerialize(validators);
  let extraSeal =Buffer.alloc(65);
  return Buffer.concat([extraVanity,validatorsBytes,extraSeal]);
}

function extraDataSerialize(validators) {
  let n = validators.length;
  let arr = [];
  for(let i = 0;i<n;i++){
    let validator = validators[i];
    arr.push(Buffer.from(web3.utils.hexToBytes(validator.consensusAddr)));
  }
  return Buffer.concat(arr);
}

function validatorUpdateRlpEncode(validators) {
  let n = validators.length;
  let vals = [];
  for(let i = 0;i<n;i++) {
    vals.push([
      validators[i].consensusAddr,
      validators[i].bscFeeAddr,
      validators[i].feeAddr,
      validators[i].votingPower,
    ]);
  }
  let pkg = [0x00, vals];
  return web3.utils.bytesToHex(RLP.encode(pkg));
}

extraValidatorBytes = generateExtradata(validators);
validatorSetBytes = validatorUpdateRlpEncode(validators);

exports = module.exports = {
  extraValidatorBytes: extraValidatorBytes,
  validatorSetBytes: validatorSetBytes,
}
