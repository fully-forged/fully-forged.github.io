---
layout: post
title:  "The Problem of State"
date:   2015-07-03 09:18:23
categories: javascript patterns
---

When we build client-side applications, most of the problems we face are related to state management: what elements on screen need to be in sync with each other, how do we track changes locally and from the server, how do we effectively handle computed properties (like a user’s complete address when it’s composed by separate pieces of data).

What can we do to tame this complexity? In this post we’ll explore some ideas and lay out the basis for a unified strategy.
