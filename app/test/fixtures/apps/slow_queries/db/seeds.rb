author = Author.create!(name: "Ada")
10.times do |index|
  post = Post.create!(author: author, title: "Post #{index}", status: index.even? ? "published" : "draft", body: "Fixture")
  3.times { |comment_index| post.comments.create!(body: "Comment #{comment_index}") }
end

WideReport.create!(account_id: 1, title: "Quarterly", category: "finance", region: "NA", owner_email: "owner@example.com")
