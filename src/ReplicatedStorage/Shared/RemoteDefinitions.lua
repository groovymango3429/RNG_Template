--!strict
return {
    FolderName = "Remotes",
    Entries = {
        { Name = "RequestInitialState", ClassName = "RemoteFunction" },
        { Name = "RollRequest", ClassName = "RemoteFunction" },
        { Name = "ToggleAutoRoll", ClassName = "RemoteFunction" },
        { Name = "ClaimDailyReward", ClassName = "RemoteFunction" },
        { Name = "ClaimPlaytimeReward", ClassName = "RemoteFunction" },
        { Name = "RequestRebirth", ClassName = "RemoteFunction" },
        { Name = "PromptGamepassPurchase", ClassName = "RemoteFunction" },
        { Name = "PromptDeveloperProductPurchase", ClassName = "RemoteFunction" },
        { Name = "StateUpdated", ClassName = "RemoteEvent" },
        { Name = "RollResult", ClassName = "RemoteEvent" },
        { Name = "Notification", ClassName = "RemoteEvent" },
    },
}
