---
layout: post
title:  "Prototyping an analytics service with PostgreSQL and Clojure"
date:   2015-03-16 09:00:00
categories: clojure postgresql
---

During our last hack day I decided to work on a proof of concept for an
analytics service, with the goal of being able to instrument any of our running
applications (both server side and client side) and expose the data with a
restful api and a web sockets interface (for eventual dashboards, etc.).
