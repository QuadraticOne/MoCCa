module MoCCa.Nozzle.MinimumLength
( minimumLengthNozzle
, wallPoints
, Point (..)
, DesignParameters (..)
, asCSVDegrees
, pointNames
) where

import qualified MoCCa.FlowTables.Isentropic as IFT
import qualified MoCCa.Util.Maths as Maths
import qualified Data.List as List

type Coordinate = (Double, Double)
data PointType = Throat | Flow | Wall deriving (Show, Eq)
data Point = Point { riemannInvariants :: (Double, Double)
                   , machNumber :: Double
                   , machAngle :: Double
                   , flowAngle :: Double
                   , prandtlMeyerFunction :: Double
                   , position :: Coordinate
                   , pointType :: PointType
                   } deriving (Show)

-- | Small value used for float comparison to zero.
eps :: Double
eps = 1e-8

-- | Extract the ascending Riemann invariant from the point.
ascendingInvariant :: Point -> Double
ascendingInvariant = fst . riemannInvariants

-- | Extract the descending Riemann invariant from the point.
descendingInvariant :: Point -> Double
descendingInvariant = snd . riemannInvariants

-- | Determine the angles of the characteristic lines coming from
-- the given point.
characteristicAngles :: Point -> (Double, Double)
characteristicAngles p = 
    let theta = flowAngle p
        mu = machAngle p
    in (theta + mu, theta - mu)

-- | Retrieve the x-coordinate of the given point.
x :: Point -> Double
x = fst . position

-- | Retrieve the y-coordinate of the given point.
y :: Point -> Double
y = snd . position

data DesignParameters = DesignParameters { gamma :: Double
                                         , exitMachNumber :: Double
                                         , tableMinimumMachNumber :: Double
                                         , tableMachNumberStep :: Double
                                         , thetaMin :: Double
                                         , numberOfCharacteristics :: Int
                                         } deriving (Show)

-- | Generate an isentropic flow table using the specified parameters.
tableFor :: DesignParameters -> IFT.IsentropicFlowTable
tableFor params = IFT.generateFlowTable (gamma params)
    (tableMinimumMachNumber params) (tableMachNumberStep params)

-- | Generate n equally spaced starting angles for characteristic
-- lines between the two limits.
generateStartingAngles :: Int -> (Double, Double) -> [Double]
generateStartingAngles n (min, max) = 
    let dtheta = (max - min) / (fromIntegral (n - 1))
    in [min + (fromIntegral i) * dtheta | i <- [0..n - 1]]

-- | Find the nozzle angle in radians immediately after the throat such
-- that the flow is uniform at the exit.
nozzleThroatAngle :: IFT.IsentropicFlowTable -> Double -> Double
nozzleThroatAngle table exitMachNumber =
    case IFT.lookupMachNumber table exitMachNumber of
        Just row -> 0.5 * IFT.prandtlMeyerFunction row
        Nothing  -> error "table does not contain the requested Mach number"

-- | Find the mirrored version of the point, finding the properties of the
-- equivalent point on the opposite side of the centreline.
mirror :: Point -> Point
mirror p =
    Point { riemannInvariants = swapTuple . riemannInvariants $ p
          , machNumber = machNumber p
          , machAngle = machAngle p
          , flowAngle = (-1) * flowAngle p
          , prandtlMeyerFunction = prandtlMeyerFunction p
          , position = (x p, (-1) * (y p))
          , pointType = pointType p
          }
    where
        swapTuple (a, b) = (b, a)

-- | Create a point and populate its field, assuming that it is located
-- at the top of the throat and its flow angle is given.
createThroatPoint :: IFT.IsentropicFlowTable -> Double -> Point
createThroatPoint table angle =
    Point { riemannInvariants = (0, 2 * angle)
          , machNumber = IFT.machNumber tableRow
          , machAngle = IFT.machAngle tableRow
          , flowAngle = angle
          , prandtlMeyerFunction = angle
          , position = (0, 1)
          , pointType = Throat
          }
    where
        tableRow = case IFT.lookupPrandtlMeyerFunction table angle of
            Just r  -> r
            Nothing -> error "table does not contain the requested P-M value"

-- | Calculate the properties of a point on the centreline which is
-- assumed to be on the same characteristic line as the given throat point.
createFlowPoint :: IFT.IsentropicFlowTable -> Point -> Point -> Point
createFlowPoint table a b =
    Point { riemannInvariants = (ascendingInvariant a, descendingInvariant b)
          , machNumber = m
          , machAngle = mu
          , flowAngle = theta
          , prandtlMeyerFunction = nu
          , position = pointPosition a b theta mu
          , pointType = Flow
          }
    where
        tableRow = case IFT.lookupPrandtlMeyerFunction table nu of
            Just r  -> r
            Nothing -> error "table does not contain the requested P-M value"
        nu = 0.5 * (ascendingInvariant a + descendingInvariant b)
        theta = 0.5 * (descendingInvariant b - ascendingInvariant a)
        m = IFT.machNumber tableRow
        mu = IFT.machAngle tableRow
        pointPosition a' b' theta' mu' =
            let xp = let xNumerator = (x b') * (tan abp) - (x a') * (tan aap)
                         yNumerator = (y a') - (y b')
                         denominator = tan abp - tan aap
                     in (xNumerator + yNumerator) / denominator
                yp = (y a') + (xp - (x a')) * (tan aap)
            in (xp, yp)
            where
                aap = 0.5 * ((flowAngle a' + machAngle a') + (theta' + mu'))
                abp = 0.5 * ((flowAngle b' - machAngle b') + (theta' - mu'))

-- | Calculate the flow state at a point on the wall of the nozzle, given a
-- point in free flow upstream of the new point, and the closest point along
-- the wall.  Assume the angle of the wall is set to create uniform flow.
createWallPoint :: IFT.IsentropicFlowTable -> Double -> Point -> Point -> Point
createWallPoint table exitMachNumber a b =
    Point { riemannInvariants = (ascendingInvariant a, 0)
          , machNumber = machNumber a
          , machAngle = machAngle a
          , flowAngle = flowAngle a
          , prandtlMeyerFunction = prandtlMeyerFunction a
          , position = pointPosition a b 
          , pointType = Wall
          }
    where
        pointPosition a' b' =
            let xp = let xNumerator = (x b') * (tan abw) - (x a') * (tan aaw)
                         yNumerator = (y a') - (y b')
                         denominator = tan abw - tan aaw
                     in (xNumerator + yNumerator) / denominator
                yp = (y a') + (xp - (x a')) * (tan aaw)
            in (xp, yp)
            where
                aaw = (flowAngle a' + machAngle a')
                abw = 0.5 * (flowAngle b + flowAngle a)

-- | Find the properties of all the free flow points on the next characteristic
-- line along from the given one, and append to it the properties of the flow
-- at the point where that characteristic line meets the wall.
calculateNextCharacteristic :: IFT.IsentropicFlowTable -> Double
    -> Point -> [Point] -> Point -> [Point]
calculateNextCharacteristic table exitMachNumber pointToMirror
    previousCharacteristicPoints previousWallPoint =
    nextCharacteristicPoints ++ [nextWallPoint]
    where
        nextCharacteristicPoints = tail $ scanl (createFlowPoint table)
            (mirror pointToMirror) $ previousCharacteristicPoints
        nextWallPoint = createWallPoint table exitMachNumber
            (last nextCharacteristicPoints) previousWallPoint

-- | Calculate the flow state at a number of points along a series of characteristic
-- lines, until there are no more points left to propagate.
calculateCharacteristics :: IFT.IsentropicFlowTable -> Double
    -> Point -> [Point] -> Point -> [Point] -> [Point]
calculateCharacteristics table exitMachNumber pointToMirror
    previousCharacteristicPoints previousWallPoint accumulatedPoints
    | lastPoint = accumulatedPoints ++ calculateNextCharacteristic table
        exitMachNumber pointToMirror previousCharacteristicPoints previousWallPoint
    | otherwise =
        let nextDescendingPoints = middle nextCharacteristicPoints
            nextPointToMirror = head nextDescendingPoints
            nextWallPoint = last nextCharacteristicPoints
            nextAccumulatedPoints = accumulatedPoints ++ nextCharacteristicPoints
        in calculateCharacteristics table exitMachNumber nextPointToMirror
            nextDescendingPoints nextWallPoint nextAccumulatedPoints
    where
        lastPoint = length previousCharacteristicPoints <= 1
        nextCharacteristicPoints = calculateNextCharacteristic table
            exitMachNumber pointToMirror previousCharacteristicPoints
            previousWallPoint
        middle = init . tail

-- | Calculate the flow state at all the characteristic points of a nozzle,
-- given the desired design parameters.
minimumLengthNozzle :: DesignParameters -> [Point]
minimumLengthNozzle params = startingPoints ++ downstreamPoints
    where
        table = tableFor params
        mExit = exitMachNumber params
        startingPoints =
            let thetaMin' = thetaMin params
                thetaMax' = nozzleThroatAngle table mExit
                startingAngles = generateStartingAngles
                    (numberOfCharacteristics params) (thetaMin', thetaMax')
            in map (createThroatPoint table) startingAngles
        downstreamPoints = calculateCharacteristics table mExit
            (head startingPoints) startingPoints (last startingPoints) []

-- | From a list of points, extract only those which sit on the wall
-- of the nozzle.
wallPoints :: [Point] -> [Point]
wallPoints = filter ((== Wall) . pointType)

-- | Convert the given point to a series of comma-separated values,
-- rounding each one to the given number of decimal places, with all
-- angles represented in degrees.
asCSVDegrees :: Int -> Point -> String
asCSVDegrees decimalPlaces p =
    let (rPlus, rMinus) = riemannInvariants p
        theta = Maths.toDegrees . flowAngle $ p
        nu = Maths.toDegrees . prandtlMeyerFunction $ p
        m = machNumber p
        mu = Maths.toDegrees . machAngle $ p
        (thetaPlusMu, thetaMinusMu) = mapTuple (Maths.toDegrees)
            . characteristicAngles $ p
            where mapTuple f (a, b) = (f a, f b)
        (x, y) = mapTuple zeroIfSmall (position p)
    in List.intercalate "," . map (Maths.roundAndFormat decimalPlaces) $
        [rPlus, rMinus, theta, nu, m, mu, thetaPlusMu, thetaMinusMu, x, y]
    where
        mapTuple f (a, b) = (f a, f b)
        zeroIfSmall x = if abs x > eps then x else 0.0

-- | Generate point names for the given parameters.  Throad points are
-- named with letters, while flow and wall points are named with numbers.
pointNames :: DesignParameters -> [String]
pointNames params =
    let nc = numberOfCharacteristics params
    in (take nc (map (\c -> [c]) ['a'..'z'])) ++ (map (show) [1..])
