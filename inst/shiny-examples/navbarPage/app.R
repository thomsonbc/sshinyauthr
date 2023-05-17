library(shiny)

# login tab ui to be rendered on launch
login_tab <- tabPanel(
  title = icon("lock"), 
  value = "login", 
  sshinyauthr::loginUI("login")
)

# additional tabs to be added after login
home_tab <- tabPanel(
  title = icon("user"),
  value = "home",
  column(
    width = 12, 
    tags$h2("User Information"),
    verbatimTextOutput("user_data")
  )
)

data_tab <- tabPanel(
  title = icon("table"),
  value = "data",
  column(
    width = 12, 
    uiOutput("data_title"),
    DT::DTOutput("table")
  )
)

# initial app UI with only login tab
ui <- navbarPage(
  title = "sshinyauthr example",
  id = "tabs", # must give id here to add/remove tabs in server
  collapsible = TRUE,
  login_tab
)

server <- function(input, output, session) {
  # hack to add the logout button to the navbar on app launch 
  insertUI(
    selector = ".navbar .container-fluid .navbar-collapse",
    ui = tags$ul(
      class="nav navbar-nav navbar-right",
      tags$li(
        div(
          style = "padding: 10px; padding-top: 8px; padding-bottom: 0;",
          sshinyauthr::logoutUI("logout")
        )
      )
    )
  )
  
# call the sshinyauthr login and logout server modules
credentials <- sshinyauthr::sshLoginServer(
    id = "login",
    log_out = reactive(logout_init()),
    host = '127.0.0.1',
    port = 22,
    manager_env = 'USER',
    reload_on_logout = FALSE,
    cookie_logins = FALSE
  )
  
  logout_init <- sshinyauthr::logoutServer(
    id = "logout",
    active = reactive(credentials()$user_auth)
  )
  
  observeEvent(credentials()$user_auth, {
    # if user logs in successfully
    if (credentials()$user_auth) { 
      # remove the login tab
      removeTab("tabs", "login")
      # add home tab 
      appendTab("tabs", home_tab, select = TRUE)
      # render user data output
      output$user_data <- renderPrint({ dplyr::glimpse(credentials()$info) })
      # add data tab
      appendTab("tabs", data_tab)
      # render data tab title and table depending on permissions
      user_permission <- credentials()$info$permissions
      if (isTRUE(credentials()$manager)) {
        output$data_title <- renderUI(tags$h2("Storms data. Permissions: admin"))
        output$table <- DT::renderDT({ dplyr::storms[1:100, 1:11] })
      } else{
        output$data_title <- renderUI(tags$h2("Starwars data. Permissions: standard"))
        output$table <- DT::renderDT({ dplyr::starwars[, 1:10] })
      }
    }
  })
}

shinyApp(ui, server)