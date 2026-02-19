defmodule SCRWeb.CoreComponents do
  use Phoenix.Component

  attr :title, :string, required: true
  attr :rest, :global

  def header(assigns) do
    ~H"""
    <header {@rest}>
      <div class="header-content">
        <h1><%= @title %></h1>
      </div>
    </header>
    """
  end

  attr :href, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def link(assigns) do
    ~H"""
    <a href={@href} class={@class}><%= render_slot(@inner_block) %></a>
    """
  end

  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class="card"><%= render_slot(@inner_block) %></div>
    """
  end
end
