--!strict

--[[
UI PROGRESSION
==============
Location:
StarterPlayer.StarterPlayerScripts.UIManager.UIHandler.UIProgression

UIHandler also exposes it as UI.Progression.

TEMPLATES
- UIProgression.ProgressionTemp > Icon
- UIProgression.Feedbacktemp > Icon and Mult

No Text option uses ProgressionTemp. Supplying Text uses Feedbacktemp and changes
Mult.Text. Both templates are pooled.

TRANSFER
UIProgression.PlayTransfer(startGuiOrPosition, endGui, 10, {
    Icon = "Cash",
    RandomStart = true,
    AnimateEndpoint = true,
    PlaySound = true,
    Sound = "Cash",
})

FEEDBACK TEXT
UIProgression.PlayTransfer(nil, endGui, 5, {
    Icon = "Cash",
    Text = "x5",
})

BURST
UIProgression.PlayBurst({
    Icon = "Coin",
    Text = "+ COINS",
    MinCount = 12,
    MaxCount = 20,
    Fade = true,       -- default true; fades throughout the downward fall
    BurstRadius = 420, -- optional; 420 is the wider default
})

FILL A BAR PER ICON ARRIVAL
UIProgression.PlayTransfer(nil, endGui, 10, {
    Icon = "Cash",
    FillBar = fillBar,
    TextRoot = barRoot,
    CurrentValue = 20,
    NewValue = 50,
    MaxValue = 100,
})

ORDINARY UI BAR
UIProgression.AnimateBar(fillBar, 20, 70, 100, {
    FillDirection = "LeftToRight",
    PlaySound = true,
    Sound = "BarFill",
})

Supported directions:
LeftToRight, RightToLeft, TopToBottom, BottomToTop
]]

return { Name = "UIProgression", Version = 4 }
