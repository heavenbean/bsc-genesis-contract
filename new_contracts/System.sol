pragma solidity 0.6.4;

contract System {

	bool public alreadyInit;

	uint32 public constant CODE_OK = 0;
	uint32 public constant ERROR_FAIL_DECODE = 100;

	uint16 constant public myChainID = 0x07CD;

	address public constant VALIDATOR_CONTRACT_ADDR = 0x0000000000000000000000000000000000001000;
	address public constant SLASH_CONTRACT_ADDR = 0x0000000000000000000000000000000000001001;
	address public constant SYSTEM_REWARD_ADDR = 0x0000000000000000000000000000000000001002;
	address public constant GOV_HUB_ADDR = 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4;


	modifier onlyCoinbase() {
		require(msg.sender == block.coinbase, "the message sender must be the block producer");
		_;
	}

	modifier onlyNotInit() {
		require(!alreadyInit, "the contract already init");
		_;
	}

	modifier onlyInit() {
		require(alreadyInit, "the contract not init yet");
		_;
	}

	modifier onlySlash() {
		require(msg.sender == SLASH_CONTRACT_ADDR, "the message sender must be slash contract");
		_;
	}

	modifier onlyGov() {
		require(msg.sender == GOV_HUB_ADDR, "the message sender must be governance contract");
		_;
	}

	modifier onlyValidatorContract() {
		require(msg.sender == VALIDATOR_CONTRACT_ADDR, "the message sender must be validatorSet contract");
		_;
	}

	// Not reliable, do not use when need strong verify
	function isContract(address addr) internal view returns (bool) {
		uint size;
		assembly { size := extcodesize(addr) }
		return size > 0;
	}
}
