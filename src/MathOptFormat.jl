module MathOptFormat

const VERSION = "0.0"

using DataStructures, JSON, MathOptInterface

# we use an ordered dict to make the JSON printing nicer
const Object = OrderedDict{String, Any}

const MOI = MathOptInterface
const MOIU = MOI.Utilities

MOIU.@model(MOFModel,
    (ZeroOne, Integer),
    (EqualTo, GreaterThan, LessThan, Interval, Semicontinuous, Semiinteger),
    (Reals, Zeros, Nonnegatives, Nonpositives, SecondOrderCone,
        RotatedSecondOrderCone, GeometricMeanCone, RootDetConeTriangle,
        RootDetConeSquare, LogDetConeTriangle, LogDetConeSquare,
        PositiveSemidefiniteConeTriangle, PositiveSemidefiniteConeSquare,
        ExponentialCone, DualExponentialCone),
    (PowerCone, DualPowerCone, SOS1, SOS2),
    (SingleVariable,),
    (ScalarAffineFunction, ScalarQuadraticFunction),
    (VectorOfVariables,),
    (VectorAffineFunction, VectorQuadraticFunction)
)

include("read.jl")
include("write.jl")

end
