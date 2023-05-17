library(shiny)
library(dplyr)
library(lubridate)
library(DBI)
library(RSQLite)

# setup and connect to an in memory SQLite db
db <- dbConnect(SQLite(), ":memory:")
dbCreateTable(db, "sessionids", c(user = "TEXT", sessionid = "TEXT", login_time = "TEXT"))

# a user who has not visited the app for this many days
# will be asked to login with user name and password again
cookie_expiry <- 7 # Days until session expires

# This function must accept two parameters: user and sessionid. It will be called whenever the user
# successfully logs in with a password.  This function saves to your database.

add_sessionid_to_db <- function(user, sessionid, conn = db) {
  tibble(user = user, sessionid = sessionid, login_time = as.character(now())) %>%
    dbWriteTable(conn, "sessionids", ., append = TRUE)
}

# This function must return a data.frame with columns user and sessionid  Other columns are also okay
# and will be made available to the app after log in as columns in credentials()$user_auth

get_sessionids_from_db <- function(conn = db, expiry = cookie_expiry) {
  dbReadTable(conn, "sessionids") %>%
    mutate(login_time = ymd_hms(login_time)) %>%
    as_tibble() %>%
    filter(login_time > now() - days(expiry))
}

ui <- fluidPage(
  # add logout button UI
  div(class = "pull-right", sshinyauthr::logoutUI(id = "logout")),
  # add login panel UI function
  sshinyauthr::loginUI(id = "login"),
  # setup table output to show user info after login
  verbatimTextOutput("user_data")
)

server <- function(input, output, session) {
  
  # Export reactive values for testing
  exportTestValues(
    auth_status = credentials()$user_auth,
    auth_info   = credentials()$info
  )
  
  # call login module supplying data frame, user and password cols and reactive trigger
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
  
  output$user_data <- renderPrint({
    # use req to only render results when credentials()$user_auth is TRUE
    req(credentials()$user_auth)
    glimpse(credentials()$info)
  })
}

shinyApp(ui = ui, server = server)