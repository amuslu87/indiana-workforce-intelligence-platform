library(shiny)
library(bslib)
library(DBI)
library(odbc)
library(dplyr)
library(plotly)
library(DT)

fmt <- function(x, digits=0) {
  ifelse(
    is.na(x),
    "Unavailable",
    formatC(x, format="f", digits=digits, big.mark=",")
  )
}

chart <- function(p,y="") {
  layout(
    p,
    paper_bgcolor="#151c29",
    plot_bgcolor="#151c29",
    font=list(color="#edf2fa"),
    xaxis=list(gridcolor="#303a49"),
    yaxis=list(title=y,gridcolor="#303a49"),
    margin=list(l=75,r=20,t=25,b=65)
  )
}

source("recruitment.R",local=TRUE)

ui <- page_fluid(
  title="Indiana Recruitment Intelligence",

  theme=bs_theme(
    version=5,
    bg="#0d111a",
    fg="#edf2fa",
    primary="#38d9ff"
  ),

  tags$style(HTML("
    .card {
      background:#151c29;
      border:1px solid #303a49;
      margin-bottom:12px;
    }
    .metric {
      font-size:2rem;
      font-weight:700;
      color:#38d9ff;
    }
    .dataTables_wrapper {
      color:#edf2fa;
    }
    .dataTables_scrollHead {
      background:#151c29;
    }
    .shiny-input-container {
      width:100%;
    }
  ")),

  div(
    class="p-3",
    h2("INDIANA | Recruitment Intelligence"),
    p("State Government Recruitment Analytics"),
    actionButton("refresh","Refresh data")
  ),

  recruitment_ui("recruitment")
)

server <- function(input,output,session) {
  recruitment_server(
    "recruitment",
    reactive(input$refresh)
  )
}

shinyApp(ui,server)
