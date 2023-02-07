// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IWETHGateway.sol";

library LibLendingPool {
    address constant lendingPool = 0x4F01AeD16D97E3aB5ab2B501154DC9bb0F1A5A2C;
    IWETHGateway constant wethGateway = IWETHGateway(0x8a47F74d1eE0e2edEB4F3A7e64EF3bD8e11D27C8);

    function supply(uint256 supplyAmount) external {
        wethGateway.depositETH{value: supplyAmount }(lendingPool, address(this), 0);
    }

    function withdraw(uint256 withdrawalAmount, address to) external {
        wethGateway.withdrawETH(lendingPool, withdrawalAmount, to);
    }
    
    function approve(address _token, uint256 amount) external {
        IERC20(_token).approve(address(lendingPool), amount);
    }
    
    function _approveGateway(address _token, uint256 _amount) external {
        IERC20(_token).approve(address(wethGateway), _amount);
    }
}