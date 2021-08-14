pragma solidity 0.6.4;

import "./System.sol";
import "./lib/BytesToTypes.sol";
import "./lib/Memory.sol";
import "./interface/ISlashIndicator.sol";
import "./interface/IValidatorSet.sol";
import "./lib/SafeMath.sol";
import "./lib/RLPDecode.sol";
import "./lib/CmnPkg.sol";


contract ValidatorSet is IValidatorSet, System {

	using SafeMath for uint256;

	using RLPDecode for *;

	// will not transfer value less than 0.1 coin for validators
	uint256 constant public DUSTY_INCOMING = 1e17;

	uint8 public constant JAIL_MESSAGE_TYPE = 1;
	uint8 public constant VALIDATORS_UPDATE_MESSAGE_TYPE = 0;

	uint256 public constant MAX_NUM_OF_VALIDATORS = 41;

	bytes public constant INIT_VALIDATORSET_BYTES = hex"f84580f842f840949fb29aac15b9a4b7f17c3385939b007540f4d791949fb29aac15b9a4b7f17c3385939b007540f4d791949fb29aac15b9a4b7f17c3385939b007540f4d79164";

	uint32 public constant ERROR_UNKNOWN_PACKAGE_TYPE = 101;
	uint32 public constant ERROR_FAIL_CHECK_VALIDATORS = 102;
	uint32 public constant ERROR_LEN_OF_VAL_MISMATCH = 103;
	uint32 public constant ERROR_RELAYFEE_TOO_LARGE = 104;

	// for future governance
	address public SuperAdminAddr; // super admin can change any external addresses
	address public ValidatorManager; // future Validator management contract

	/*********************** state of the contract **************************/
	Validator[] public currentValidatorSet;
	uint256 public totalInComing;

	// key is the `consensusAddress` of `Validator`,
	// value is the index of the element in `currentValidatorSet`.
	mapping(address =>uint256) public currentValidatorSetMap;
	uint256 public numOfJailed;

	struct Validator{
		address consensusAddress;
		address payable feeAddress;
		address BBCFeeAddress;
		uint64  votingPower;

		// only in state
		bool jailed;
		uint256 incoming;
	}

	/*********************** cross chain package **************************/
	struct IbcValidatorSetPackage {
		uint8  packageType;
		Validator[] validatorSet;
	}

	/*********************** modifiers **************************/
	modifier noEmptyDeposit() {
		require(msg.value > 0, "deposit value is zero");
		_;
	}

	/*********************** events **************************/
	event validatorSetUpdated();
	event validatorJailed(address indexed validator);
	event validatorEmptyJailed(address indexed validator);
	event systemTransfer(uint256 amount);
	event directTransfer(address payable indexed validator, uint256 amount);
	event directTransferFail(address payable indexed validator, uint256 amount);
	event deprecatedDeposit(address indexed validator, uint256 amount);
	event validatorDeposit(address indexed validator, uint256 amount);
	event validatorMisdemeanor(address indexed validator, uint256 amount);
	event validatorFelony(address indexed validator, uint256 amount);
	event failReasonWithStr(string message);
	event superAdminChanged(address adminAddr);
	event validatorManagerChanged(address managerAddr);

	modifier onlyAdmin() {
		require(msg.sender == SuperAdminAddr, 'Super admin only!');
		_;
	}

	modifier onlyValidatorManager() {
		require(msg.sender == ValidatorManager, 'ValidatorManager only!');
		_;
	}

	function changeSuperAdmin(address newAddr) public onlyAdmin {
		SuperAdminAddr = newAddr;
		emit superAdminChanged(newAddr);
	}

	function changeValidatorManager(address newAddr) public onlyAdmin {
		ValidatorManager = newAddr;
		emit validatorManagerChanged(newAddr);
	}

	/*********************** init **************************/
	function init() external onlyNotInit {
		(IbcValidatorSetPackage memory validatorSetPkg, bool valid)= decodeValidatorSetSynPackage(INIT_VALIDATORSET_BYTES);
		require(valid, "failed to parse init validatorSet");
		for (uint i = 0;i<validatorSetPkg.validatorSet.length;i++) {
			currentValidatorSet.push(validatorSetPkg.validatorSet[i]);
			currentValidatorSetMap[validatorSetPkg.validatorSet[i].consensusAddress] = i+1;
		}

		// set admin address for managing validator
		SuperAdminAddr = GOV_HUB_ADDR;
		ValidatorManager = GOV_HUB_ADDR;

		alreadyInit = true;
	}

	/*********************** Validator management Implement **************************/
	function handleSynPackage(uint8, bytes calldata msgBytes) onlyInit onlyValidatorManager external returns(bytes memory responsePayload) {
		(IbcValidatorSetPackage memory validatorSetPackage, bool ok) = decodeValidatorSetSynPackage(msgBytes);
		if (!ok) {
			return CmnPkg.encodeCommonAckPackage(ERROR_FAIL_DECODE);
		}
		uint32 resCode;
		if (validatorSetPackage.packageType == VALIDATORS_UPDATE_MESSAGE_TYPE) {
			resCode = updateValidatorSet(validatorSetPackage.validatorSet);
		} else if (validatorSetPackage.packageType == JAIL_MESSAGE_TYPE) {
			if (validatorSetPackage.validatorSet.length != 1) {
			emit failReasonWithStr("length of jail validators must be one");
			resCode = ERROR_LEN_OF_VAL_MISMATCH;
		} else {
			resCode = jailValidator(validatorSetPackage.validatorSet[0]);
		}
		} else {
			resCode = ERROR_UNKNOWN_PACKAGE_TYPE;
		}
		if (resCode == CODE_OK) {
			return new bytes(0);
		} else {
			return CmnPkg.encodeCommonAckPackage(resCode);
		}
	}

	/*********************** External Functions **************************/
	function deposit(address valAddr) external payable onlyCoinbase onlyInit noEmptyDeposit{
		uint256 value = msg.value;
		uint256 index = currentValidatorSetMap[valAddr];
		if (index>0) {
			Validator storage validator = currentValidatorSet[index-1];
			if (validator.jailed) {
				emit deprecatedDeposit(valAddr,value);
			} else {
				totalInComing = totalInComing.add(value);
				validator.incoming = validator.incoming.add(value);
				emit validatorDeposit(valAddr,value);
			}
		} else {
			// get incoming from deprecated validator;
			emit deprecatedDeposit(valAddr,value);
		}
	}

	function jailValidator(Validator memory v) internal returns (uint32) {
		uint256 index = currentValidatorSetMap[v.consensusAddress];
		if (index==0 || currentValidatorSet[index-1].jailed) {
			emit validatorEmptyJailed(v.consensusAddress);
			return CODE_OK;
		}
		uint n = currentValidatorSet.length;
		bool shouldKeep = (numOfJailed >= n-1);
		// will not jail if it is the last valid validator
		if (shouldKeep) {
			emit validatorEmptyJailed(v.consensusAddress);
			return CODE_OK;
		}
		numOfJailed ++;
		currentValidatorSet[index-1].jailed = true;
		emit validatorJailed(v.consensusAddress);
		return CODE_OK;
	}

	function updateValidatorSet(Validator[] memory validatorSet) internal returns (uint32) {
		// do verify.
		(bool valid, string memory errMsg) = checkValidatorSet(validatorSet);
		if (!valid) {
			emit failReasonWithStr(errMsg);
			return ERROR_FAIL_CHECK_VALIDATORS;
		}

		Validator[] memory validatorSetTemp = validatorSet; // fix error: stack too deep, try removing local variables

		// TRANSFER REWARD
		for (uint i = 0;i<currentValidatorSet.length;i++) {
			if (currentValidatorSet[i].incoming >= DUSTY_INCOMING) {
				bool success = currentValidatorSet[i].feeAddress.send(currentValidatorSet[i].incoming);
				if (success) {
					emit directTransfer(currentValidatorSet[i].feeAddress, currentValidatorSet[i].incoming);
				} else {
					emit directTransferFail(currentValidatorSet[i].feeAddress, currentValidatorSet[i].incoming);
				}
			}
		}

		// step 4: do dusk transfer
		if (address(this).balance>0) {
			emit systemTransfer(address(this).balance);
			address(uint160(SYSTEM_REWARD_ADDR)).transfer(address(this).balance);
		}
		// step 5: do update validator set state
		totalInComing = 0;
		numOfJailed = 0;
		if (validatorSetTemp.length>0) {
			doUpdateState(validatorSetTemp);
		}

		// step 6: clean slash contract
		ISlashIndicator(SLASH_CONTRACT_ADDR).clean();
		emit validatorSetUpdated();
		return CODE_OK;
	}

	function getValidators()external view returns(address[] memory) {
		uint n = currentValidatorSet.length;
		uint valid = 0;
		for (uint i = 0;i<n;i++) {
			if (!currentValidatorSet[i].jailed) {
				valid ++;
			}
		}
		address[] memory consensusAddrs = new address[](valid);
		valid = 0;
		for (uint i = 0;i<n;i++) {
			if (!currentValidatorSet[i].jailed) {
				consensusAddrs[valid] = currentValidatorSet[i].consensusAddress;
				valid ++;
			}
		}
		return consensusAddrs;
	}

	function getIncoming(address validator)external view returns(uint256) {
		uint256 index = currentValidatorSetMap[validator];
		if (index<=0) {
			return 0;
		}
		return currentValidatorSet[index-1].incoming;
	}

	/*********************** For slash **************************/
	function misdemeanor(address validator)external onlySlash override{
		uint256 index = currentValidatorSetMap[validator];
		if (index <= 0) {
			return;
		}
		// the actually index
		index = index - 1;
		uint256 income = currentValidatorSet[index].incoming;
		currentValidatorSet[index].incoming = 0;
		uint256 rest = currentValidatorSet.length - 1;
		emit validatorMisdemeanor(validator,income);
		if (rest==0) {
			// should not happen, but still protect
			return;
		}
		uint256 averageDistribute = income/rest;
		if (averageDistribute!=0) {
			for (uint i=0;i<index;i++) {
				currentValidatorSet[i].incoming = currentValidatorSet[i].incoming + averageDistribute;
			}
			uint n = currentValidatorSet.length;
			for (uint i=index+1;i<n;i++) {
				currentValidatorSet[i].incoming = currentValidatorSet[i].incoming + averageDistribute;
			}
		}
		// averageDistribute*rest may less than income, but it is ok, the dust income will go to system reward eventually.
	}

	function felony(address validator)external onlySlash override {
		uint256 index = currentValidatorSetMap[validator];
		if (index <= 0) {
			return;
		}
		// the actually index
		index = index - 1;
		uint256 income = currentValidatorSet[index].incoming;
		uint256 rest = currentValidatorSet.length - 1;
		if (rest==0) {
			// will not remove the validator if it is the only one validator.
			currentValidatorSet[index].incoming = 0;
			return;
		}
		emit validatorFelony(validator,income);
		delete currentValidatorSetMap[validator];
		// It is ok that the validatorSet is not in order.
		if (index != currentValidatorSet.length-1) {
			currentValidatorSet[index] = currentValidatorSet[currentValidatorSet.length-1];
			currentValidatorSetMap[currentValidatorSet[index].consensusAddress] = index + 1;
		}
		currentValidatorSet.pop();
		uint256 averageDistribute = income/rest;
		if (averageDistribute!=0) {
			uint n = currentValidatorSet.length;
			for (uint i=0;i<n;i++) {
				currentValidatorSet[i].incoming = currentValidatorSet[i].incoming + averageDistribute;
			}
		}
		// averageDistribute*rest may less than income, but it is ok, the dust income will go to system reward eventually.
	}

	/*********************** Internal Functions **************************/

	function checkValidatorSet(Validator[] memory validatorSet) private pure returns(bool, string memory) {
		if (validatorSet.length > MAX_NUM_OF_VALIDATORS){
			return (false, "the number of validators exceed the limit");
		}
		for (uint i = 0;i<validatorSet.length;i++) {
			for (uint j = 0;j<i;j++) {
				if (validatorSet[i].consensusAddress == validatorSet[j].consensusAddress) {
					return (false, "duplicate consensus address of validatorSet");
				}
			}
		}
		return (true,"");
	}

	function doUpdateState(Validator[] memory validatorSet) private{
		uint n = currentValidatorSet.length;
		uint m = validatorSet.length;

		for (uint i = 0;i<n;i++) {
			bool stale = true;
			Validator memory oldValidator = currentValidatorSet[i];
			for (uint j = 0;j<m;j++) {
				if (oldValidator.consensusAddress == validatorSet[j].consensusAddress) {
					stale = false;
					break;
				}
			}
			if (stale) {
				delete currentValidatorSetMap[oldValidator.consensusAddress];
			}
		}

		if (n>m) {
			for (uint i = m;i<n;i++) {
				currentValidatorSet.pop();
			}
		}
		uint k = n < m ? n:m;
		for (uint i = 0;i<k;i++) {
			if (!isSameValidator(validatorSet[i], currentValidatorSet[i])) {
				currentValidatorSetMap[validatorSet[i].consensusAddress] = i+1;
				currentValidatorSet[i] = validatorSet[i];
			} else {
				currentValidatorSet[i].incoming = 0;
			}
		}
		if (m>n) {
			for (uint i = n;i<m;i++) {
				currentValidatorSet.push(validatorSet[i]);
				currentValidatorSetMap[validatorSet[i].consensusAddress] = i+1;
			}
		}
	}

	function isSameValidator(Validator memory v1, Validator memory v2) private pure returns(bool) {
		return v1.consensusAddress == v2.consensusAddress && v1.feeAddress == v2.feeAddress && v1.BBCFeeAddress == v2.BBCFeeAddress && v1.votingPower == v2.votingPower;
	}

	//rlp encode & decode function
	function decodeValidatorSetSynPackage(bytes memory msgBytes) internal pure returns (IbcValidatorSetPackage memory, bool) {
		IbcValidatorSetPackage memory validatorSetPkg;

		RLPDecode.Iterator memory iter = msgBytes.toRLPItem().iterator();
		bool success = false;
		uint256 idx=0;
		while (iter.hasNext()) {
			if (idx == 0) {
				validatorSetPkg.packageType = uint8(iter.next().toUint());
			} else if (idx == 1) {
				RLPDecode.RLPItem[] memory items = iter.next().toList();
				validatorSetPkg.validatorSet =new Validator[](items.length);
				for (uint j = 0;j<items.length;j++) {
					(Validator memory val, bool ok) = decodeValidator(items[j]);
					if (!ok) {
						return (validatorSetPkg, false);
					}
					validatorSetPkg.validatorSet[j] = val;
				}
				success = true;
			} else {
				break;
			}
			idx++;
		}
		return (validatorSetPkg, success);
	}

	function decodeValidator(RLPDecode.RLPItem memory itemValidator) internal pure returns(Validator memory, bool) {
		Validator memory validator;
		RLPDecode.Iterator memory iter = itemValidator.iterator();
		bool success = false;
		uint256 idx=0;
		while (iter.hasNext()) {
			if (idx == 0) {
				validator.consensusAddress = iter.next().toAddress();
			} else if (idx == 1) {
				validator.feeAddress = address(uint160(iter.next().toAddress()));
			} else if (idx == 2) {
				validator.BBCFeeAddress = iter.next().toAddress();
			} else if (idx == 3) {
				validator.votingPower = uint64(iter.next().toUint());
				success = true;
			} else {
				break;
			}
			idx++;
		}
		return (validator, success);
	}
}
