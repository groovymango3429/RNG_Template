--!strict
local MAX_ANIMATION_Y_SCALE_RATIO = 1 / 3

return {
    RootGui = "YourUiPack!",
    Panels = {
        "DailyRewards",
        "PlaytimeRewards",
        "Rewards",
        "Shop",
        "Discover",
        "Index",
        "Rebirth",
        "LeftSide",
        "LeftBottomBar",
    },
    NavigationButtons = {
        DailyRewards = { "LeftSide", "ReadyBtn" },
        Shop = { "LeftSide", "ShopBtn" },
        Index = { "LeftSide", "IndexBtn" },
        Rebirth = { "LeftSide", "RebirthBtn" },
        Discover = { "LeftBottomBar", "IconBtn03" },
        PlaytimeRewards = { "LeftBottomBar", "IconBtn05" },
    },
    ExternalPanels = {
        -- Path entries are an array of child names traversed sequentially from PlayerGui via SafeWait.FindPath.
        Shop = { "Shop", "ItemShopUI" },
    },
    ActionButtons = {
        Roll = { "LeftBottomBar", "IconBtn01" },
        AutoRoll = { "LeftBottomBar", "IconBtn02" },
        LuckProduct = { "LeftBottomBar", "IconBtn04" },
        RewardsWatch = { "Rewards", "Content", "WatchBtn" },
        Rebirth = { "Rebirth", "Content", "Btns", "RebirthBtn" },
        SkipRebirth = { "Rebirth", "Content", "Btns", "SkipRebirthBtn" },
    },
    CloseButtons = {
        DailyRewards = { "DailyRewards", "Header", "CloseBtn" },
        PlaytimeRewards = { "PlaytimeRewards", "Header", "CloseBtn" },
        Rewards = { "Rewards", "Header", "CloseBtn" },
        Index = { "Index", "Main", "Header", "CloseBtn" },
        Rebirth = { "Rebirth", "Header", "CloseBtn" },
    },
    DiscoverOrder = { "Normal", "Candy", "Gold", "Diamond", "Rainbow", "Vulcan" },
    FeaturedProductKey = "LuckBurst",
    RebirthSkipProductKey = "SkipRebirth",
    Loading = {
        ScreenGuiName = "LoadingScreen",
        PreloadAssetsFolder = "Assets",
        FadeDuration = 0.35,
    },
    Rolling = {
        ScreenGuiName = "Rolling",
        MainPath = { "Main" },
        ImagePath = { "ImageLabel" },
        PetNamePath = { "PetName" },
        RarityPath = { "Rarity" },
        RarityStrokePath = { "Rarity", "UIStroke" },
        FinalPosition = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
    },
    AutoRoll = {
        RollPanelTopPosition = UDim2.new(0.5, 0, 0.08, 0),
        RollPanelTopAnchorPoint = Vector2.new(0.5, 0),
        RollingPanelTopPosition = UDim2.new(0.5, 0, 0.1, 0),
        RollingPanelTopAnchorPoint = Vector2.new(0.5, 0),
        RollingScale = 0.5,
        RollingSpacingScale = 0.42,
        MaxAnimationYScale = MAX_ANIMATION_Y_SCALE_RATIO,
    },
}
