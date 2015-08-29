require 'liquid'
require_relative 'ff/posts'

Liquid::Template.register_filter(FF::Posts)
