pragma solidity 0.4.24;

import "../interfaces/IChai.sol";
import "./Ownable.sol";
import "./ERC20Bridge.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

/**
* @title ChaiConnector
* @dev This logic allows to use Chai token (https://github.com/dapphub/chai)
*/
contract ChaiConnector is Ownable, ERC20Bridge {
    using SafeMath for uint256;

    bytes32 internal constant CHAI_TOKEN = 0xe529dd1fa310362a861f9a51ed0d07b46ef28d89054300cd2734814ddfcfd449; // keccak256(abi.encodePacked("chaiToken"))
    bytes32 internal constant INVESTED_AMOUNT = 0xb6afb3323c9d7dc0e9dab5d34c3a1d1ae7739d2224c048d4ee7675d3c759dd1b; // keccak256(abi.encodePacked("investedAmount"))

    uint256 internal constant RAY = 10**27;

    /**
    * @dev Fixed point multiplication
    * @return Truncated value of x * y
    */
    function rmul(uint256 x, uint256 y) internal pure returns (uint256) {
        return x.mul(y) / RAY;
    }

    /**
    * @dev Fixed point division
    * @return Ceiled value of x / y
    */
    function rdivup(uint256 x, uint256 y) internal pure returns (uint256) {
        return x.mul(RAY).add(y.sub(1)) / y;
    }

    /**
    * @dev Initializes chai token
    * @param _chai Chai token contract address
    */
    function initializeChaiToken(address _chai) external onlyOwner {
        require(address(chaiToken()) == address(0));
        require(address(IChai(_chai).daiToken()) == address(erc20token()));
        addressStorage[CHAI_TOKEN] = _chai;
        erc20token().approve(_chai, uint256(-1));
    }

    /**
    * @dev Withdraws all invested tokens, pays remaining interest, removes chai token from contrac storage
    * @param recipient Account address to receive remaining interest
    */
    function removeChaiToken(address recipient) external onlyOwner {
        exit(investedAmountInDai());
        chaiToken().transfer(recipient, chaiBalance());
        erc20token().approve(chaiToken(), 0);
        delete addressStorage[CHAI_TOKEN];
    }

    /**
    * @dev Pays all available interest, in Chai tokens
    * @param recipient Account address to receive available interest
    */
    function payInterest(address recipient) external onlyOwner {
        // since investedAmountInChai() returns a ceiled value,
        // the value of chaiBalance() - investedAmountInChai() will be floored,
        // leading to excess remaining chai balance
        chaiToken().transfer(recipient, chaiBalance() - investedAmountInChai());

        require(dsrBalance() >= investedAmountInDai());
    }

    /**
    * @dev Pays interest, in Chai tokens
    * @param recipient Account address to receive available interest
    * @param amount Amount of Chai tokens to transfer
    */
    function payInterest(address recipient, uint256 amount) external onlyOwner {
        // check that the remaining chai balance will be sufficient to cover all invested DAI tokens
        require(chaiBalance() - amount >= investedAmountInChai());
        chaiToken().transfer(recipient, amount);

        require(dsrBalance() >= investedAmountInDai());
    }

    /**
    * @dev Returns current used chai contract
    * @return chai contract address
    */
    function chaiToken() public view returns (IChai) {
        return IChai(addressStorage[CHAI_TOKEN]);
    }

    /**
    * @dev Evaluates bridge balance for tokens, holded in DSR
    * @return Balance in dai, truncated
    */
    function dsrBalance() public view returns (uint256) {
        uint256 chi = pot().chi();
        return rmul(chi, chaiBalance());
    }

    /**
    * @dev Evaluates bridge balance in Chai tokens
    * @return Balance in chai, exact
    */
    function chaiBalance() public view returns (uint256) {
        return chaiToken().balanceOf(address(this));
    }

    function setInvestedAmointInDai(uint256 amount) internal {
        uintStorage[INVESTED_AMOUNT] = amount;
    }

    /**
    * @dev Evaluates exact current invested amount, id DAI
    * @return Value in DAI
    */
    function investedAmountInDai() public view returns (uint256) {
        return uintStorage[INVESTED_AMOUNT];
    }

    function pot() internal view returns (IPot) {
        return chaiToken().pot();
    }

    /**
    * @dev Evaluates amount of chai tokens that is sufficent to cover 100% of the invested DAI
    * @return Amount in chai, ceiled
    */
    function investedAmountInChai() internal returns (uint256) {
        // solhint-disable-next-line not-rely-on-time
        uint256 chi = (now > pot().rho()) ? pot().drip() : pot().chi();
        return rdivup(investedAmountInDai(), chi);
    }

    /**
    * @dev Invests DAI into Chai
    * @param amount Amount of DAI to invest
    */
    function join(uint256 amount) internal {
        setInvestedAmointInDai(investedAmountInDai() + amount);
        chaiToken().join(address(this), amount);
    }

    /**
    * @dev Redeems DAI from Chai, the total redeemed amount will be at least equal to specified amount
    * @param amount Amount of DAI to redeem
    */
    function exit(uint256 amount) internal {
        uint256 invested = investedAmountInDai();
        if (amount >= invested) {
            chaiToken().draw(address(this), invested);
            setInvestedAmointInDai(0);
        } else if (amount > 0) {
            uint256 initialDaiBalance = erc20token().balanceOf(address(this));
            chaiToken().draw(address(this), amount);
            uint256 redeemed = erc20token().balanceOf(address(this)) - initialDaiBalance;
            setInvestedAmointInDai(redeemed < invested ? invested - redeemed : 0);
        }
    }
}