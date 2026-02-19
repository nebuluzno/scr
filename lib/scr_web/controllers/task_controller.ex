defmodule SCRWeb.TaskController do
  use SCRWeb, :controller

  def index(conn, _params) do
    tasks = SCR.Agents.MemoryAgent.list_tasks()
    render(conn, :index, tasks: tasks)
  end

  def new(conn, _params) do
    render(conn, :new, csrf_token: get_csrf_token())
  end

  def create(conn, %{"task" => task_params}) do
    description = Map.get(task_params, "description", "")
    
    if description == "" do
      conn
      |> put_flash(:error, "Task description cannot be empty")
      |> redirect(to: ~p"/tasks/new")
    else
      # Generate a task ID
      task_id = UUID.uuid4()
      
      # Ensure MemoryAgent is running (ignore if already started)
      case SCR.Supervisor.start_agent("memory_1", :memory, SCR.Agents.MemoryAgent, %{}) do
        {:ok, _} -> :ok
        {:error, :already_started} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
      
      # Ensure PlannerAgent is running (ignore if already started)
      case SCR.Supervisor.start_agent("planner_1", :planner, SCR.Agents.PlannerAgent, %{}) do
        {:ok, _} -> :ok
        {:error, :already_started} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
      
      # Send the task to PlannerAgent
      task_msg = SCR.Message.task("web", "planner_1", %{
        task_id: task_id,
        description: description
      })
      
      SCR.Supervisor.send_to_agent("planner_1", task_msg)
      
      conn
      |> put_flash(:info, "Task submitted successfully!")
      |> redirect(to: ~p"/tasks")
    end
  end
end
