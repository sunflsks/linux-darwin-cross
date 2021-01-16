#!/bin/sh

c++ -c ldid.cpp
cc -c lookup2.c
mkdir -p out
c++ *.o -o out/ldid "$DESTDIR/$PREFIX/lib/libplist-2.0.a" -lcrypto -lpthread
