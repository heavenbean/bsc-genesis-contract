pragma solidity 0.6.4;
import "./System.sol";

contract SystemReward is System {
	uint256 public constant MAX_REWARDS = 1e18;

	event rewardTo(address indexed to, uint256 amount);
	event rewardEmpty();
	event receiveDeposit(address indexed from, uint256 amount);

	receive() external payable{
		if (msg.value>0) {
			emit receiveDeposit(msg.sender, msg.value);
		}
	}


	function claimRewards(address payable to, uint256 amount) external onlyGov returns(uint256) {
		uint256 actualAmount = amount < address(this).balance ? amount : address(this).balance;
		if (actualAmount > MAX_REWARDS) {
			actualAmount = MAX_REWARDS;
		}
		if (actualAmount>0) {
			to.transfer(actualAmount);
			emit rewardTo(to, actualAmount);
		} else {
			emit rewardEmpty();
		}
		return actualAmount;
	}

	function isOperator(address addr) external pure returns (bool) {
		return addr == GOV_HUB_ADDR;
	}
}