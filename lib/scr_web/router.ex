defmodule SCRWeb.Router do
  use SCRWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SCRWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SCRWeb do
    pipe_through :browser

    live "/", DashboardLive
    get "/agents", AgentController, :index
    get "/agents/:id", AgentController, :show
    get "/tasks", TaskController, :index
    get "/tasks/new", TaskController, :new
    post "/tasks", TaskController, :create
    get "/metrics", MetricsController, :index
    get "/memory", MemoryController, :index
    get "/tools", ToolController, :index
    post "/tools/execute", ToolController, :execute
  end

  # Other scopes may use custom stacks.
  # scope "/api", SCRWeb do
  #   pipe_through :api
  # end
end
