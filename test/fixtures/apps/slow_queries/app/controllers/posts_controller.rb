class PostsController < ApplicationController
  def index
    @posts = Post.all
  end

  def published
    @posts = Post.where(status: "published").order(created_at: :desc)
  end
end
