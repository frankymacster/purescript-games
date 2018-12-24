module Snake where

import Prelude -- must be explicitly imported
import Effect (Effect)
import Effect.Console (log)
import Effect.Random (randomInt)
import Data.Array (length, uncons, slice, (:), last)
import Data.Array.Partial (head)
import Data.Functor
import Data.Generic.Rep
import Data.Int
import Data.Maybe
import Data.Traversable
import Data.Tuple
import Graphics.Canvas (closePath, lineTo, moveTo, fillPath,
                        setFillStyle, arc, rect, getContext2D,
                        getCanvasElementById, Context2D, Rectangle)
import Partial.Unsafe (unsafePartial)
import Signal (Signal, runSignal, foldp, sampleOn, map4)
import Signal.DOM (keyPressed)
import Signal.Time (Time, second, every)
import Test.QuickCheck.Gen -- for randomness

import SignalM

type Point = Tuple Int Int

randomPoint :: Int -> Int -> Gen Point
randomPoint xmax ymax = 
    do
      x <- chooseInt 1 xmax
      y <- chooseInt 1 ymax
      pure $ Tuple x y

--MODEL
type Snake = Array Point

type Model = {xd :: Int, yd :: Int, size :: Int, mouse:: Point, snake :: Snake, dir :: Point, alive :: Boolean, prev :: Maybe Point}
-- prev is the last place the snake was. This is to erase easily.

init' :: Gen Model
init' = do
  let xmax = 25
  let ymax = 25
  ms <- untilM (\p -> p /= Tuple 1 1) (randomPoint xmax ymax)
  pure {xd : xmax, yd : ymax, size : 10, mouse : ms, snake : [Tuple 1 1], dir: Tuple 1 0, alive : true, prev : Nothing}

init :: Effect Model
init = evalGenD init'

--UPDATE
inBounds :: Point -> Model -> Boolean
inBounds (Tuple x y) m = 
  (x > 0) && (y > 0) && (x <= m.xd) && (y <= m.yd)

checkOK :: Point -> Model -> Boolean
checkOK pt m = 
  let
    s = m.snake
  in
    m.alive && (inBounds pt m) && not (pt `elem` (body s))

step :: Partial => Point -> Model -> Gen Model --need 2nd argument to be Eff for foldp
step dir m = 
  let
    -- override the direction with the input, unless there is no input (corresponding to (0,0))
    d = if dir /= Tuple 0 0
        then dir
        else m.dir
    s = m.snake
    hd = (head s + d)
  in
    if checkOK hd m
      then 
        if (hd == m.mouse) 
        then 
            do 
              newMouse <- untilM (\pt -> not (pt `elem` s || pt == hd)) (randomPoint m.xd m.yd)
              pure $ m { snake = hd : s
                       , mouse = newMouse
                       , dir = d
                       , prev = Nothing -- snake grows; nothing is deleted
                       }
        else (pure $ m { snake = hd : (body s)
                      , dir = d
                      , prev = last s -- snake moves; the last pixel is deleted
                      })
      else (pure $ m { alive = false, prev = Nothing})

--VIEW
colorSquare :: Int -> Point -> String -> Context2D -> Effect Unit
colorSquare size (Tuple x y) color ctx = do
  setFillStyle ctx color
  fillPath ctx $ rect ctx $ square size x y

square :: Int -> Int -> Int -> Rectangle
square size x y = { x: toNumber $ size*x
                  , y: toNumber $ size*y
                  , width: toNumber $ size
                  , height: toNumber $ size
                  }

renderStep :: Partial => Model -> Effect Unit
renderStep m = 
  void do
        let s=m.snake
        Just canvas <- getCanvasElementById "canvas"
        ctx <- getContext2D canvas
        colorSquare m.size (head s) snakeColor ctx
        --black 
        case m.prev of
          Nothing -> colorSquare m.size (m.mouse) mouseColor ctx
          Just pt -> colorSquare m.size pt bgColor ctx
--clearRect ctx $ square m.size x y
        --make use of the fact: either we draw the mouse or erase the tail, not both, at any one step

--forall eff. Partial => Model -> (Eff (canvas :: CANVAS | eff) Unit)
render :: Partial => Model -> (Effect Unit)
render m = 
  void do
        let s = m.snake
        let size = m.size
        Just canvas <- getCanvasElementById "canvas"
        ctx <- getContext2D canvas
        --walls
        setFillStyle ctx wallColor
        fillPath ctx $ rect ctx
                     { x: 0.0
                     , y: 0.0
                     , width: toNumber $ size*(m.xd + 2)
                     , height: toNumber $ size*(m.yd + 2)
                     }
        --interior
        setFillStyle ctx bgColor
        fillPath ctx $ rect ctx
                     { x: toNumber $ size
                     , y: toNumber $ size
                     , width: toNumber $ size*(m.xd)
                     , height: toNumber $ size*(m.yd)
                     }
        --snake 
        _ <- for s (\x -> colorSquare m.size x snakeColor ctx)
        --mouse
        colorSquare m.size (m.mouse) mouseColor ctx


--SIGNALS
--(dom :: DOM | e)
inputDir :: Effect (Signal Point)
inputDir = 
    let 
        f = \l u d r -> ifs [Tuple l $ Tuple (-1) 0, Tuple u $ Tuple 0 (-1), Tuple d $ Tuple 0 1, Tuple r $ Tuple 1 0] $ Tuple 0 0
--note y goes DOWN
    in
      map4 f <$> (keyPressed 37) <*> (keyPressed 38) <*> (keyPressed 40) <*> (keyPressed 39)

--(dom :: DOM | e)
input :: Effect (Signal Point)
input = sampleOn (fps 20.0) <$> inputDir

fps :: Time -> Signal Time
fps x = every (second/x)

--MAIN
--(random :: RANDOM, dom :: DOM)
main :: Effect Unit
main = --onDOMContentLoaded 
    void $ unsafePartial do
      --draw the board
      gameStart <- init
      render gameStart
      -- create the signals
      dirSignal <- input
      -- need to be in effect monad in order to get a keyboard signal
      game <- foldpR step gameStart dirSignal
      runSignal (map renderStep game)

--Utility functions
ifs:: forall a. Array (Tuple Boolean a) -> a -> a
ifs li z = case uncons li of
             Just {head : Tuple b y, tail : tl} -> if b then y else ifs tl z
             Nothing         -> z 

body :: forall a. Array a -> Array a
body li = slice 0 ((length li) - 1) li

untilM :: forall m a. (Monad m) => (a -> Boolean) -> m a -> m a
untilM cond ma = 
    do 
      x <- ma
      if cond x then pure x else untilM cond ma
        
bindR :: forall a b m. (Monad m) => m a -> m b -> m b
bindR mx my = mx >>= const my

infixl 0 bindR as >>

white = "#FFFFFF"
black = "#000000"
red = "#FF0000"
yellow = "#FFFF00"
green = "#008000"
blue = "#0000FF"
purple = "800080"

snakeColor = white
bgColor = black
mouseColor = red
wallColor = green
