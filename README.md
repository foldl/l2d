l2d
===

An interpreter for 2d & l2d language, written in Pascal.

Build
===

This is a Lazarus console application.

2D Language
===

2D Language is a defined in [ICFP Programming Contest 2006](http://boundvariable.org/).

See Ohmega.txt which is extracted from the codex.

```
,.....|...............................,
:plus | *==================*          :
------#>!send [(W,S),(W,E)]!-+        :
:     v *==================* v        :
:*=============* |     *============* :
:!case N of S,E!-#---->!send [(N,E)]!--
:*=============* v     *============* :
:     |  *========*  *===============*:
:     +->!use plus!->!send[(Inl W,E)]!-
:        *========*  *===============*:
,.....................................,
```

L2D
===

L2D is a text-favored 2d. Wires have names.


A l2d translation of `plus`:

```
module (a -> N, b -> W) ==> plus2 ==> (bPlus0, b_Plus_a) 
    // repeat b 
    (b -> W) ==> send [(W, S), (W, E)] ==> (S -> bCopyS, E -> bCopyE) 
    
    // if a == 0, output b 
    (a -> N) ==> case N of S, E ==> (S -> aMinus1, E -> aIsZero) 
    (bCopyE -> N, aIsZero -> W) ==> send [(N, E)] ==> (E -> bPlus0) 

    // calc: b + (a - 1) 
    (bCopyS -> W, aMinus1 -> N) ==> use plus2 ==> (E -> b_Plus_a_Minus1) 
    (b_Plus_a_Minus1 -> W) ==> send [(Inl W, E)] ==> (E -> b_Plus_a)
end
```

