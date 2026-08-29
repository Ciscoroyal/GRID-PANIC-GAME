--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldProgression = require(
	ReplicatedStorage:WaitForChild("Systems"):WaitForChild("WorldProgression"):WaitForChild("WorldController")
)

export type WorldTarget = WorldProgression.WorldTarget
export type ProgressTarget = WorldProgression.ProgressTarget
export type FeedbackBatch = WorldProgression.FeedbackBatch
export type CollectionOptions = WorldProgression.CollectionOptions
export type StageOptions = WorldProgression.StageOptions
export type ProgressOptions = WorldProgression.ProgressOptions
export type ProgressHandle = WorldProgression.ProgressHandle

local WorldProgressionClient = {}

function WorldProgressionClient.PlayCollection(
	startTarget: WorldTarget,
	endTarget: WorldTarget,
	count: number,
	options: CollectionOptions?
): FeedbackBatch
	return WorldProgression.PlayCollection(startTarget, endTarget, count, options)
end

function WorldProgressionClient.BindProgressBar(
	target: ProgressTarget,
	options: ProgressOptions?
): ProgressHandle
	return WorldProgression.BindProgressBar(target, options)
end

function WorldProgressionClient.Init()
end

function WorldProgressionClient.Destroy()
	WorldProgression.DestroyAll()
end

return WorldProgressionClient
