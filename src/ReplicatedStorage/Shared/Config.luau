local Config = {}

Config.Monetization = {
	Passes = {
		
	},

	Products = {
		
	},

	Announce = {
		Enabled = true,
		Color   = Color3.fromRGB(70, 255, 110),

		Format        = "%s just bought %s for %s Robux!",
		NoPriceFormat = "%s just bought %s!",

		-- Product Kinds that never announce.
		SkipKinds = { Wins = true, WinsPart = true },
	},
	
	Store = {
		PanelPath  = { "Main", "Frames", "Store", "ScrollingFrame" },
		ButtonName = "Robux",
		PriceName  = "Price",

		Entries = {
			{ Path = { "StarterPack" },   Product = "StarterPack", HideWhenOwned = true, Bundle = "StarterPack" },
			{ Path = { "VIP" },           Pass    = "DoubleWins",  HideWhenOwned = true },
			{ Path = { "Coins", "10k" },  Product = "LuckySpins"  },
			{ Path = { "Coins", "100k" }, Product = "LuckySpin10" },
			{ Path = { "Spins", "100k" }, Product = "LuckySpin25" },
			{ Path = { "Spins", "10k" }, Product = "LuckySpin5" },
			{ Path = { "Mil" },           Product = "LuckySpin50" },
		}
	},

	Attributes = {
		ProductId  = "ProductId",
		PassId     = "PassId",
		ProductKey = "ProductKey",
		PassKey    = "PassKey",

		PriceLabels = { "Price", "Title" },
	},
}
	
	Config.ScrollFrames = {
		Padding = 8, -- pixels added past the measured content
	}


return Config
