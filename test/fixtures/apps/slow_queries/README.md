# Slow Queries Fixture App

This fixture supports the `query_health` cookbook. It is intentionally small and Rails-like rather than a complete generated app. Query collectors should be able to scan these files without booting a second Rails application.

Intentional smells:

1. N+1 association access: `PostsController#index` assigns `@posts = Post.all`, and the view calls `post.author.name`.
2. Missing index: `PostsController#published` filters `Post.where(status: ...)`, while `db/schema.rb` has no `index_posts_on_status`.
3. Unnecessary `SELECT *`: `WideReportSearch#call` uses `WideReport.select("*")` even though callers only need two columns.
4. Counter query: the posts index view calls `post.comments.count` instead of using a counter cache.
