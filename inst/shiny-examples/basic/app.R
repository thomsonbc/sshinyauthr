library(shiny)

ui <- fluidPage(
  # add logout button UI
  div(class = "pull-right", sshinyauthr::logoutUI(id = "logout")),
  # add login panel UI function
  shinyauthr::loginUI(id = "login"),
  # setup table output to show user info after login
  tableOutput("user_table"),
  # setup table output to show another table after manager login
  tableOutput("manager_table")
)

server <- function(input, output, session) {
  # call login module supplying host and port
  # set manager_env as 'USER' environment variable and login with standard user details
  # ssh on local machine needs to be enabled 
  credentials <- sshinyauthr::sshLoginServer(
    id = "login",
    log_out = reactive(logout_init()),
    host = '127.0.0.1',
    port = 22,
    manager_env = 'USER',
    reload_on_logout = FALSE,
    cookie_logins = FALSE
  )
  
  # call the logout module with reactive trigger to hide/show
  logout_init <- sshinyauthr::logoutServer(
    id = "logout",
    active = reactive(credentials()$user_auth)
  )
  
  output$user_table <- renderTable({
    # use req to only render results when credentials()$user_auth is TRUE
    req(credentials()$user_auth)
    credentials()$info
  })
  
  output$manager_table <- renderTable({
    # use req to only render results when credentials()$manager is TRUE
    req(credentials()$manager)
    data.frame(manager=TRUE)
  })
}

if (interactive()) shinyApp(ui = ui, server = server)