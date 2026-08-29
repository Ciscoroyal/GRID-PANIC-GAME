local Config = require(script.Parent.Config)
local formatNumber = require(script.Parent.FormatNumber)
local SUFFIXES = { "", "K", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No", "Dc" }

local Util = {}

function Util.ClosestPointOnPart(position: Vector3, part: BasePart): Vector3
	local localPoint = part.CFrame:PointToObjectSpace(position)
	local half = part.Size * 0.5

	return part.CFrame:PointToWorldSpace(Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	))
end

function Util.DistanceToPart(position: Vector3, part: BasePart): number
	return (Util.ClosestPointOnPart(position, part) - position).Magnitude
end

function Util.IsInsidePart(position: Vector3, part: BasePart, padding: number?): boolean
	local localPoint = part.CFrame:PointToObjectSpace(position)
	local half = part.Size * 0.5
	local slack = padding or 0

	return math.abs(localPoint.X) <= half.X + slack
		and math.abs(localPoint.Y) <= half.Y + slack
		and math.abs(localPoint.Z) <= half.Z + slack
end

function Util.WeightedPick(entries)
	local total = 0
	for _, entry in entries do
		total += entry.Weight
	end

	if total <= 0 then
		return entries[1]
	end

	local roll = math.random() * total
	for _, entry in entries do
		roll -= entry.Weight
		if roll <= 0 then
			return entry
		end
	end

	return entries[#entries]
end

function Util.Abbreviate(value: number): string
	if value < Config.Format.WholeNumbersBelow then
		return tostring(math.floor(value))
	end

	return formatNumber.FormatCompact(value)
end

function Util.Robux(price: number?, loadingText: string?): string
	local Config = require(script.Parent.Config)
	local icon = Config.Format.RobuxIcon

	if price == nil then
		return icon .. (loadingText or "...")
	end

	return icon .. Util.Abbreviate(price)
end

return Util
