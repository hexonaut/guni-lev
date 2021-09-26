// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

interface CurvePoolLike {
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

interface GUNITokenLike is IERC20 {
    function mint(uint256 mintAmount, address receiver) external returns (
        uint256 amount0,
        uint256 amount1,
        uint128 liquidityMinted
    );
    function burn(uint256 burnAmount, address receiver) external returns (
        uint256 amount0,
        uint256 amount1,
        uint128 liquidityBurned
    );
    function getMintAmounts(uint256 amount0Max, uint256 amount1Max) external view returns (uint256 amount0, uint256 amount1, uint256 mintAmount);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IERC3156FlashBorrower {
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32);
}

interface IERC3156FlashLender {
    function maxFlashLoan(
        address token
    ) external view returns (uint256);
    function flashFee(
        address token,
        uint256 amount
    ) external view returns (uint256);
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool);
}

interface GemJoinLike {
    function vat() external view returns (address);
    function ilk() external view returns (bytes32);
    function gem() external view returns (address);
    function dec() external view returns (uint256);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

interface DaiJoinLike {
    function vat() external view returns (address);
    function dai() external view returns (address);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

interface VatLike {
    function ilks(bytes32) external view returns (
        uint256 Art,  // [wad]
        uint256 rate, // [ray]
        uint256 spot, // [ray]
        uint256 line, // [rad]
        uint256 dust  // [rad]
    );
    function hope(address usr) external;
    function frob (bytes32 i, address u, address v, address w, int dink, int dart) external;
    function dai(address) external view returns (uint256);
}

contract GuniLev is IERC3156FlashBorrower {

    enum Action {WIND, UNWIND}

    VatLike public immutable vat;
    bytes32 public immutable ilk;
    GemJoinLike public immutable join;
    DaiJoinLike public immutable daiJoin;
    GUNITokenLike public immutable guni;
    IERC20 public immutable dai;
    IERC20 public immutable otherToken;
    IERC3156FlashLender public immutable lender;
    CurvePoolLike public immutable curvePool;

    constructor(GemJoinLike _join, DaiJoinLike _daiJoin, IERC20 _otherToken, IERC3156FlashLender _lender, CurvePoolLike _curvePool) {
        vat = _join.vat();
        ilk = _join.ilk();
        join = _join;
        daiJoin = _daiJoin;
        guni = GUNITokenLike(_join.gem());
        dai = _daiJoin.dai();
        otherToken = _otherToken;
        lender = _lender;
        curvePool = _curvePool;
    }

    // --- math ---
    uint256 constant RAY = 10 ** 27;
    function divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x + (y - 1)) / y;
    }

    function wind(
        uint256 principal,
        uint256 leverage,
        uint256 slippage
    ) external {
        bytes memory data = abi.encode(Action.WIND, msg.sender, principal, leverage, slippage);
        initFlashLoan(data, principal*leverage);
    }

    function initFlashLoan(bytes memory data, uint256 amount) internal {
        uint256 _allowance = dai.allowance(address(this), address(lender));
        uint256 _fee = lender.flashFee(address(dai), amount);
        uint256 _repayment = amount + _fee;
        dai.approve(address(lender), _allowance + _repayment);
        lender.flashLoan(this, address(dai), amount, data);
    }

    function onFlashLoan(
        address initiator,
        address _token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(
            msg.sender == address(lender),
            "FlashBorrower: Untrusted lender"
        );
        require(
            initiator == address(this),
            "FlashBorrower: Untrusted loan initiator"
        );
        (Action action, address usr, uint256 principal, uint256 leverage, uint256 slippage) = abi.decode(data, (Action, address, uint256, uint256, uint256));
        if (action == Action.WIND) {
            _wind(usr, amount + fee, principal, leverage, slippage);
        } else if (action == Action.UNWIND) {
            
        }
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function _wind(address usr, uint256 totalOwed, uint256 principal, uint256 leverage, uint256 slippage) internal {
        // TODO: Convert some of the DAI to USDC

        // Mint G-UNI
        (,, uint256 mintAmount) = guni.getMintAmounts(IERC20(guni.token0()).balanceOf(address(this)), IERC20(guni.token1()).balanceOf(address(this)));
        (,, uint256 guniBalance) = guni.mint(mintAmount, address(this));

        // Open / Re-enforce vault
        guni.approve(address(join), guniBalance);
        join.join(address(usr), guniBalance);
        (,uint256 rate,,,) = vat.ilks(ilk);
        uint256 dart = divup(guniBalance * RAY, rate);      // TODO: This should draw max dai against the vault, not just the new collateral
        vat.frob(ilk, address(usr), address(usr), address(this), int256(guniBalance), int256(dart));
        daiJoin.exit(address(this), vat.dai(address(this)) / RAY);

        uint256 daiBalance = dai.balanceOf(address(this));
        if (daiBalance > totalOwed) {
            // Send extra dai to user
            dai.transfer(usr, daiBalance - totalOwed);
        } else if (daiBalance < totalOwed) {
            // Pull remaining dai needed from usr
            dai.transferFrom(usr, address(this), totalOwed - daiBalance);
        }

        // Send any remaining dust from other token to user as well
        otherToken.transfer(usr, otherToken.balanceOf(address(this)));
    }

}
