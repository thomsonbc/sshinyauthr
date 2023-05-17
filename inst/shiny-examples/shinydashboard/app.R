library(shiny)
library(shinydashboard)
library(dplyr)
library(glue)
library(sshinyauthr)
library(RSQLite)
library(DBI)
library(lubridate)

# How many days should sessions last?
cookie_expiry <- 7

# This function must return a data.frame with columns user and sessionid.  Other columns are also okay
# and will be made available to the app after log in.

get_sessions_from_db <- function(conn = db, expiry = cookie_expiry) {
  dbReadTable(conn, "sessions") %>%
    mutate(login_time = ymd_hms(login_time)) %>%
    as_tibble() %>%
    filter(login_time > now() - days(expiry))
}

# This function must accept two parameters: user and sessionid. It will be called whenever the user
# successfully logs in with a password.

add_session_to_db <- function(user, sessionid, conn = db) {
  tibble(user = user, sessionid = sessionid, login_time = as.character(now())) %>%
    dbWriteTable(conn, "sessions", ., append = TRUE)
}

db <- dbConnect(SQLite(), ":memory:")
dbCreateTable(db, "sessions", c(user = "TEXT", sessionid = "TEXT", login_time = "TEXT"))

ui <- dashboardPage(
  dashboardHeader(
    title = "sshinyauthr",
    tags$li(
      class = "dropdown",
      style = "padding: 8px;",
      sshinyauthr::logoutUI("logout")
    ),
    tags$li(
      class = "dropdown",
      tags$a(
        icon("github"),
        href = "https://github.com/thomsonbc/sshinyauthr",
        title = "See the code on github"
      )
    )
  ),
  dashboardSidebar(
    collapsed = TRUE,
    div(textOutput("welcome"), style = "padding: 20px")
  ),
  dashboardBody(
    sshinyauthr::loginUI(
      "login", 
      cookie_expiry = cookie_expiry, 
      additional_ui = tagList(
        tags$p("Test the different outputs from the sample logins below
             as well as an invalid login attempt. Ensure your local machine is able to accept SSH connections.", class = "text-center")
      )
    ),
    uiOutput("testUI")
  )
)

server <- function(input, output, session) {
  
  # call login module supplying host, port, environment variable specifying manager user(s)
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

  observe({
    if (credentials()$user_auth) {
      shinyjs::removeClass(selector = "body", class = "sidebar-collapse")
    } else {
      shinyjs::addClass(selector = "body", class = "sidebar-collapse")
    }
  })



  user_data <- reactive({
    req(credentials()$user_auth)

    if (isTRUE(credentials()$manager)) {
      dplyr::starwars[, 1:10]
    } else{
      dplyr::storms[, 1:11]
    }
  })

  output$welcome <- renderText({
    req(credentials()$user_auth)

    glue("Welcome {credentials()$info$user}")
  })

  output$testUI <- renderUI({
    req(credentials()$user_auth)

    fluidRow(
      column(
        width = 12,
        tags$h2(glue("Your permission level is: {ifelse(isTRUE(credentials()$manager), 'Manager', 'Standard')}.
                     You logged in at: {now()}.
                     Your data is: {ifelse(isTRUE(credentials()$manager), 'Starwars', 'Storms')}.")),
        box(
          width = NULL,
          status = "primary",
          title = ifelse(isTRUE(credentials()$manager), "Starwars Data", "Storms Data"),
          DT::renderDT(user_data(), options = list(scrollX = TRUE))
        )
      )
    )
  })
}

shiny::shinyApp(ui, server)
