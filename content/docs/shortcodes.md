---
title: Shortcodes
description: This article helps you get started with the shortcodes.
date: 2025-01-08
draft: true
tags:
    - "Installation"
params:
    color: red
    email: hello@5min.tech
showAuthor: true
showReadingTime: false

#layout: "simple"
---

### QR Code Shortcode
{{< qr text=https://gohugo.io />}}

### Instagram Shortcode
{{< instagram CxOWiQNP2MO >}}

### Related Posts Shortcode
{{< list title="Samples" cardView=true limit=6 where="Type" value="posts" >}}

### YouTube Shortcode
{{< youtube dQw4w9WgXcQ >}}

### Params Shortcode
We found a {{% param "color" %}} shirt.

Email me at {{% param "email" %}}.

### Ref Link
[Link basic-elements]({{% ref "/posts/basic-elements" %}})

### Image
{{< figure src="img/blowfish_logo.png" alt="Sample Image" caption="This is a sample image." size="10%" >}}

### Random Image
![Img](https://picsum.photos/800/400)

### Random inage from folder img