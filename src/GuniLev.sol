// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

interface IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
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

interface UniPoolLike {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
    function swap(address, bool, int256, uint160, bytes calldata) external;
    function positions(bytes32) external view returns (uint128, uint256, uint256, uint128, uint128);
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
    function pool() external view returns (address);
}

interface CurveSwapLike {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
    function coins(uint256) external view returns (address);
}

interface GUNIRouterLike {
    function addLiquidity(
        address _pool,
        uint256 _amount0Max,
        uint256 _amount1Max,
        uint256 _amount0Min,
        uint256 _amount1Min,
        address _receiver
    )
    external
    returns (
        uint256 amount0,
        uint256 amount1,
        uint256 mintAmount
    );
}

interface GUNIResolverLike {
    function getRebalanceParams(
        address pool,
        uint256 amount0In,
        uint256 amount1In,
        uint256 price18Decimals
    ) external view returns (bool zeroForOne, uint256 swapAmount);
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
    function urns(bytes32, address) external view returns (uint256, uint256);
    function hope(address usr) external;
    function frob (bytes32 i, address u, address v, address w, int dink, int dart) external;
    function dai(address) external view returns (uint256);
}

interface SpotLike {
    function ilks(bytes32) external view returns (address pip, uint256 mat);
}

contract GuniLev is IERC3156FlashBorrower {

    enum Action {WIND, UNWIND}

    VatLike public immutable vat;
    bytes32 public immutable ilk;
    GemJoinLike public immutable join;
    DaiJoinLike public immutable daiJoin;
    SpotLike public immutable spotter;
    GUNITokenLike public immutable guni;
    IERC20 public immutable dai;
    IERC20 public immutable otherToken;
    IERC3156FlashLender public immutable lender;
    CurveSwapLike public immutable curve;
    GUNIRouterLike public immutable router;
    GUNIResolverLike public immutable resolver;
    int128 public immutable curveIndexDai;
    int128 public immutable curveIndexOtherToken;
    uint256 public immutable otherTokenTo18Conversion;

    constructor(
        GemJoinLike _join,
        DaiJoinLike _daiJoin,
        SpotLike _spotter,
        IERC20 _otherToken,
        IERC3156FlashLender _lender,
        CurveSwapLike _curve,
        GUNIRouterLike _router,
        GUNIResolverLike _resolver, 
        int128 _curveIndexDai,
        int128 _curveIndexOtherToken
    ) {
        vat = VatLike(_join.vat());
        ilk = _join.ilk();
        join = _join;
        daiJoin = _daiJoin;
        spotter = _spotter;
        guni = GUNITokenLike(_join.gem());
        dai = IERC20(_daiJoin.dai());
        otherToken = _otherToken;
        lender = _lender;
        curve = _curve;
        router = _router;
        resolver = _resolver;
        curveIndexDai = _curveIndexDai;
        curveIndexOtherToken = _curveIndexOtherToken;
        otherTokenTo18Conversion = 10 ** _otherToken.decimals();
        
        VatLike(_join.vat()).hope(address(_daiJoin));
    }

    // --- math ---
    uint256 constant RAY = 10 ** 27;

    function wind(
        uint256 principal,
        uint256 minExchangeBPS
    ) external {
        bytes memory data = abi.encode(Action.WIND, msg.sender, minExchangeBPS);
        (,uint256 mat) = spotter.ilks(ilk);
        initFlashLoan(data, principal*RAY/(mat - RAY));
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
        address,
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
        (Action action, address usr, uint256 minExchangeBPS) = abi.decode(data, (Action, address, uint256));
        if (action == Action.WIND) {
            _wind(usr, amount + fee, minExchangeBPS);
        } else if (action == Action.UNWIND) {
            
        }
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function _wind(address usr, uint256 totalOwed, uint256 minExchangeBPS) internal {
        // Calculate how much DAI we should be swapping for otherToken
        uint256 swapAmount;
        {
            (uint256 sqrtPriceX96,,,,,,) = UniPoolLike(guni.pool()).slot0();
            (, swapAmount) = resolver.getRebalanceParams(
                address(guni),
                IERC20(guni.token0()).balanceOf(address(this)),
                IERC20(guni.token1()).balanceOf(address(this)),
                ((((sqrtPriceX96*sqrtPriceX96) >> 96) * 1e18) >> 96) * 1e18 / otherTokenTo18Conversion
            );
        }

        // Swap DAI for otherToken on Curve
        dai.approve(address(curve), swapAmount);
        curve.exchange(curveIndexDai, curveIndexOtherToken, swapAmount, swapAmount * otherTokenTo18Conversion / 1e18 * minExchangeBPS / 10000);

        // Mint G-UNI
        uint256 guniBalance;
        {
            uint256 bal0 = IERC20(guni.token0()).balanceOf(address(this));
            uint256 bal1 = IERC20(guni.token1()).balanceOf(address(this));
            dai.approve(address(router), bal0);
            otherToken.approve(address(router), bal1);
            (,, guniBalance) = router.addLiquidity(address(guni), bal0, bal1, bal0 * 99 / 100, bal1 * 99 / 100, address(this));      // Slippage on this is not terribly important - use 1%
            dai.approve(address(router), 0);
            otherToken.approve(address(router), 0);
        }

        // Open / Re-enforce vault
        {
            guni.approve(address(join), guniBalance);
            join.join(address(usr), guniBalance);
            (,uint256 rate, uint256 spot,,) = vat.ilks(ilk);
            (uint256 ink, uint256 art) = vat.urns(ilk, usr);
            uint256 dart = (guniBalance + ink) * spot / rate - art;
            vat.frob(ilk, address(usr), address(usr), address(this), int256(guniBalance), int256(dart));
            daiJoin.exit(address(this), vat.dai(address(this)) / RAY);
        }

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
