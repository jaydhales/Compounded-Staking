// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IWETH} from "./interfaces/IWETH.sol";
import {ReceiptToken, RewardToken} from "./receiptToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2.sol";

contract Staker is Ownable(msg.sender) {
    IWETH weth;
    IUniswapV2Router02 uniRouter;
    ReceiptToken public receiptToken;
    RewardToken public rewardToken;
    uint256 public totalFee;
    uint256 public totalRewards;
    uint256 public lastCompounding;

    struct StakeInfo {
        uint256 totalStaked;
        uint256 totalReward;
        uint256 lastStaked;
        bool allowCompound;
    }

    mapping(address => StakeInfo) public stakers;
    mapping(address => bool) public hasStaked;
    address[] public stakerArr;

    constructor() {
        weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        uniRouter = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        receiptToken = new ReceiptToken();
        rewardToken = new RewardToken();
        lastCompounding = block.timestamp;
    }

    function stake(bool _allowCompound) public payable {
        StakeInfo storage _staker = stakers[msg.sender];

        (bool success,) = address(weth).call{value: msg.value}("");
        if (!success) revert("Staking Failed");
        uint256 _totalStaked = _staker.totalStaked + msg.value;
        uint256 _totalReward = _calculateReward(_staker);

        _staker.totalStaked = _totalStaked;
        _staker.totalReward += _totalReward;
        totalRewards += _totalReward;
        _staker.lastStaked = block.timestamp;
        _staker.allowCompound = _allowCompound;

        if (!hasStaked[msg.sender]) {
            stakerArr.push(msg.sender);
            hasStaked[msg.sender] = true;
        }

        if (_allowCompound) {
            receiptToken.mint(msg.sender, msg.value * 99 / 100);
            totalFee += msg.value * 1 / 100;
        } else {
            receiptToken.mint(msg.sender, msg.value);
        }
    }

    function autoCompound() external {
        // address[] memory _stakerArr = stakerArr;
        rewardToken.approve(address(uniRouter), type(uint256).max);
        address[] memory path;
        path[0] = address(rewardToken);
        path[1] = uniRouter.WETH();

        for (uint256 i = 0; i < stakerArr.length; i++) {
            address _addr = stakerArr[i];
            StakeInfo memory _staker = stakers[_addr];
            if (!_staker.allowCompound) {
                continue;
            }

            _staker.totalReward += _calculateReward(_staker);

            uint256[] memory _amounts =
                uniRouter.swapExactTokensForTokens(_staker.totalReward, 0, path, address(this), block.timestamp + 86400);
            uint256 wethAmount = _amounts[1];

            _staker.totalStaked += wethAmount;
            totalRewards -= _staker.totalReward;
            _staker.totalReward = 0;
            _staker.lastStaked = block.timestamp;
            receiptToken.mint(_addr, wethAmount);
        }

        uint256 _amountToRewardCompounder = _calculateCompounderReward();

        totalFee -= _amountToRewardCompounder;
        lastCompounding = block.timestamp;

        weth.transfer(msg.sender, _amountToRewardCompounder);

        rewardToken.approve(address(uniRouter), 0);
    }

    function _calculateReward(StakeInfo memory _info) internal view returns (uint256 _reward) {
        uint256 apr = 14;
        uint256 time = 365 days;
        uint256 _timeSpent = _info.lastStaked > 0 ? block.timestamp - _info.lastStaked : 0;

        _reward = (_info.totalStaked * apr * _timeSpent) / (time * 100);
    }

    function _calculateCompounderReward() internal view returns (uint256 _rew) {
        uint256 time = 30 days;
        uint256 duration = block.timestamp < (lastCompounding + time) ? block.timestamp - lastCompounding : time;

        _rew = totalFee * duration / time;
    }

    function addLiquidity(uint256 amountToMint) external payable onlyOwner {
        rewardToken.mint(address(this), amountToMint);
        rewardToken.approve(address(uniRouter), amountToMint);

        uniRouter.addLiquidityETH{value: msg.value}(
            address(rewardToken), amountToMint, 0, 0, address(this), block.timestamp + 86400
        );
    }
}
