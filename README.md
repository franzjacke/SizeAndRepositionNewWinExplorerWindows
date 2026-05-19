Every time you open a new File Explorer window it will automatically be:
  - Resized to 1/6 of 3440x1440 screen  (1146 x 720 pixels)
  - Placed in the next quadrant in this rotating sequence:

    1. Left-Top      (    0,   0)
    2. Left-Bottom   (    0, 720)
    3. Middle-Top    ( 1146,   0)
    4. Middle-Bottom ( 1146, 720)
    5. Right-Top     ( 2293,   0)
    6. Right-Bottom  ( 2293, 720)
    → then back to 1. Left-Top, and so on.

  Layout on screen (3440 x 1440):
  ┌───────────┬───────────┬───────────┐
  │  1 L-Top  │  3 M-Top  │  5 R-Top  │
  ├───────────┼───────────┼───────────┤
  │  2 L-Bot  │  4 M-Bot  │  6 R-Bot  │
  └───────────┴───────────┴───────────┘
