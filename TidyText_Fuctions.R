if (!require(tm)) {install.packages("tm")}
if (!require(wordcloud)) {install.packages("wordcloud")}
if (!require(igraph)) {install.packages("igraph")}
if (!require(ggraph)) {install.packages("ggraph")}

library(tm) 
library(tidyverse)
library(tidytext)
library(wordcloud)
library(igraph)
library(ggraph)

# +++ 

text.clean = function(x,                    # x=text_corpus
                      remove_numbers=TRUE,        # whether to drop numbers? Default is TRUE  
                      remove_stopwords=TRUE)      # whether to drop stopwords? Default is TRUE
  
{ library(tm)
  x  =  gsub("<.*?>", " ", x)               # regex for removing HTML tags
  x  =  iconv(x, "latin1", "ASCII", sub="") # Keep only ASCII characters
  x  =  gsub("[^[:alnum:]]", " ", x)        # keep only alpha numeric 
  x  =  tolower(x)                          # convert to lower case characters
  
  if (remove_numbers) { x  =  removeNumbers(x)}    # removing numbers
  
  x  =  stripWhitespace(x)                  # removing white space
  x  =  gsub("^\\s+|\\s+$", "", x)          # remove leading and trailing white space. Note regex usage
  
  # evlauate condn
  if (remove_stopwords){
    
    # read std stopwords list from my git
    stpw1 = readLines('https://raw.githubusercontent.com/sudhir-voleti/basic-text-analysis-shinyapp/master/data/stopwords.txt')
    
    # tm package stop word list; tokenizer package has the same name function, hence 'tm::'
    stpw2 = tm::stopwords('english')      
    comn  = unique(c(stpw1, stpw2))         # Union of the two lists
    stopwords = unique(gsub("'"," ",comn))  # final stop word list after removing punctuation
    
    # removing stopwords created above
    x  =  removeWords(x,stopwords)           }  # if condn ends
  
  x  =  stripWhitespace(x)                  # removing white space
  # x  =  stemDocument(x)                   # can stem doc if needed. For Later.
  
  return(x) }  # func ends

# +++

dtm_build <- function(raw_corpus, tfidf=FALSE)
{                  # func opens
  
  require(tidytext); require(tibble); require(tidyverse)
  
  # converting raw corpus to tibble to tidy DF
  textdf = data_frame(text = raw_corpus);    textdf  
  
  tidy_df = textdf %>%   
    mutate(doc = row_number()) %>%
    unnest_tokens(word, text) %>% 
    anti_join(stop_words) %>%
    group_by(doc) %>%
    count(word, sort=TRUE)
  tidy_df
  
  # evaluating IDF wala DTM
  if (tfidf == "TRUE") {
    textdf1 = tidy_df %>% 
      group_by(doc) %>% 
      count(word, sort=TRUE) %>% ungroup() %>%
      bind_tf_idf(word, doc, nn) %>%   # 'nn' is default colm name
      rename(value = tf_idf)} else { textdf1 = tidy_df %>% rename(value = n)  } 
  
  textdf1
  
  dtm = textdf1 %>% cast_sparse(doc, word, value);    dtm[1:9, 1:9]
  
  # order rows and colms putting max mass on the top-left corner of the DTM
  colsum = apply(dtm, 2, sum)    
  col.order = order(colsum, decreasing=TRUE)
  row.order = order(rownames(dtm) %>% as.numeric())
  
  dtm1 = dtm[row.order, col.order];    dtm1[1:8,1:8]
  
  return(dtm1)  }   # func ends

# testing func 2 on ibm data
# system.time({ dtm_ibm_tf = ibm %>% text.clean(., remove_numbers=FALSE) %>% 
#                            dtm_build(.) })    # 0.02 secs

# +++
# func to streamline DTM size by dropping tokens occurring too rarely or frequently
streamline_dtm <- function(dtm,  # takes dtm as input
                           min_occur=0.05,   # if token occurs in <5% of docs, drop it
                           max_occur=0.95)   # if token occurs in >95% of docs, drop it
{
  
  # drop tokens failing a min or max doc_occurrence threshold
  a0 = apply(dtm, 2, function(x) ifelse(x>0, 1, 0))
  a1 = apply(a0, 2, sum);    summary(a1)
  min_thresh = min_occur*nrow(dtm)    # drop if token occurs in < 1% of docs
  a2 = (a1 > min_thresh)
  a2_dtm = dtm[, a2];    # dim(a2_dtm)
  
  max_thresh = max_occur*nrow(dtm)     # drop if token occurs in > 99% of docs 
  a1 = apply(a2_dtm, 2, sum)
  a3 = (a1 <= max_thresh)
  a3_dtm = a2_dtm[, a3];    # dim(a3_dtm) 
  
  # drop empty rows after token set reduction. 
  a100 = apply(a3_dtm, 1, sum)
  a101.logical = (a100 > 0)
  a4_dtm = a3_dtm[a101.logical,]
  
  # reorder rownames
  a0 = order(as.numeric(rownames(a4_dtm)))
  a4_dtm = a4_dtm[a0,]          
  # rm(a0, a1, a2, a3, a2_dtm)
  
  return(a4_dtm)    # pre-processed dtm output
}  # streamline_dtm() func ends

# test-driving above func on ibm data
# system.time({ ibm_dtm_streamlined = ibm %>% 
#                                      text.clean(., remove_numbers=FALSE) %>% 
#                                      dtm_build(.) %>% 
#                                      streamline_dtm(., min_occur=0.01, max_occur=0.80) })    # 0.42 secs

# +++

build_wordcloud <- function(dtm, 
                            max.words1=150,     # max no. of words to accommodate
                            min.freq=5,       # min.freq of words to consider
                            plot.title="wordcloud"){          # write within double quotes
  
  require(wordcloud)
  if (ncol(dtm) > 20000){   # if dtm is overly large, break into chunks and solve
    
    tst = round(ncol(dtm)/100)  # divide DTM's cols into 100 manageble parts
    a = rep(tst,99)
    b = cumsum(a);rm(a)
    b = c(0,b,ncol(dtm))
    
    ss.col = c(NULL)
    for (i in 1:(length(b)-1)) {
      tempdtm = dtm[,(b[i]+1):(b[i+1])]
      s = colSums(as.matrix(tempdtm))
      ss.col = c(ss.col,s)
      print(i)      } # i loop ends
    
    tsum = ss.col
    
  } else { tsum = apply(dtm, 2, sum) }
  
  tsum = tsum[order(tsum, decreasing = T)]       # terms in decreasing order of freq
  head(tsum);    tail(tsum)
  
  # windows()  # Opens a new plot window when active
  wordcloud(names(tsum), tsum,     # words, their freqs 
            scale = c(3.5, 0.5),     # range of word sizes
            min.freq,                     # min.freq of words to consider
            max.words = max.words1,       # max #words
            colors = brewer.pal(8, "Dark2"))    # Plot results in a word cloud 
  title(sub = plot.title)     # title for the wordcloud display
  
} # func ends

# test-driving func 3 via IBM data
# system.time({ build_wordcloud(ibm_dtm_streamlined, plot.title="IBM TF wordlcoud") })    # 0.4 secs

# +++

plot.barchart <- function(dtm, num_tokens=15, fill_color="Blue")
{
  a0 = apply(dtm, 2, sum)
  a1 = order(a0, decreasing = TRUE)
  tsum = a0[a1]
  
  # plot barchart for top tokens
  test = as.data.frame(round(tsum[1:num_tokens],0))
  
  # windows()  # New plot window
  require(ggplot2)
  p = ggplot(test, aes(x = rownames(test), y = test)) + 
    geom_bar(stat = "identity", fill = fill_color) +
    geom_text(aes(label = test), vjust= -0.20) + 
    theme(axis.text.x = element_text(angle = 90, hjust = 1))
  
  plot(p) }  # func ends

# testing above func
# system.time({ plot.barchart(ibm_dtm_streamlined) })    # 0.1 secs

# +++

distill.cog = function(dtm, # input dtm
                       title="COG", # title for the graph
                       central.nodes=4,    # no. of central nodes
                       max.connexns = 5){  # max no. of connections  
  
  # first convert dtm to an adjacency matrix
  dtm1 = as.matrix(dtm)   # need it as a regular matrix for matrix ops like %*% to apply
  adj.mat = t(dtm1) %*% dtm1    # making a square symmatric term-term matrix 
  diag(adj.mat) = 0     # no self-references. So diag is 0.
  a0 = order(apply(adj.mat, 2, sum), decreasing = T)   # order cols by descending colSum
  mat1 = as.matrix(adj.mat[a0[1:50], a0[1:50]])
  
  # now invoke network plotting lib igraph
  library(igraph)
  
  a = colSums(mat1) # collect colsums into a vector obj a
  b = order(-a)     # nice syntax for ordering vector in decr order  
  
  mat2 = mat1[b, b]     # order both rows and columns along vector b  
  diag(mat2) =  0
  
  ## +++ go row by row and find top k adjacencies +++ ##
  
  wc = NULL
  
  for (i1 in 1:central.nodes){ 
    thresh1 = mat2[i1,][order(-mat2[i1, ])[max.connexns]]
    mat2[i1, mat2[i1,] < thresh1] = 0   # neat. didn't need 2 use () in the subset here.
    mat2[i1, mat2[i1,] > 0 ] = 1
    word = names(mat2[i1, mat2[i1,] > 0])
    mat2[(i1+1):nrow(mat2), match(word,colnames(mat2))] = 0
    wc = c(wc, word)
  } # i1 loop ends
  
  
  mat3 = mat2[match(wc, colnames(mat2)), match(wc, colnames(mat2))]
  ord = colnames(mat2)[which(!is.na(match(colnames(mat2), colnames(mat3))))]  # removed any NAs from the list
  mat4 = mat3[match(ord, colnames(mat3)), match(ord, colnames(mat3))]
  
  # building and plotting a network object
  graph <- graph.adjacency(mat4, mode = "undirected", weighted=T)    # Create Network object
  graph = simplify(graph) 
  V(graph)$color[1:central.nodes] = "green"
  V(graph)$color[(central.nodes+1):length(V(graph))] = "pink"
  
  graph = delete.vertices(graph, V(graph)[ degree(graph) == 0 ]) # delete singletons?
  
  plot(graph, 
       layout = layout.kamada.kawai, 
       main = title)
  
} # distill.cog func ends

# testing COG on ibm data
# system.time({ distill.cog(ibm_dtm_streamlined, "COG for IBM TF") })    # 0.27 secs

# +++

build_cog_ggraph <- function(corpus,   # text colmn only
                             max_edges = 150, 
                             drop.stop_words=TRUE,
                             new.stopwords=NULL){
  
  # invoke libraries
  library(tidyverse)
  library(tidytext)
  library(widyr)
  library(ggraph)
  
  # build df from corpus
  corpus_df = data.frame(docID = seq(1:length(corpus)), text = corpus, stringsAsFactors=FALSE)
  
  # eval stopwords condn
  if (drop.stop_words == TRUE) {stop.words = unique(c(stop_words$word, new.stopwords)) %>% 
    as_tibble() %>% rename(word=value)} else {stop.words = stop_words[2,]}
  
  # build word-pairs
  tokens <- corpus_df %>% 
    
    # tokenize, drop stop_words etc
    unnest_tokens(word, text) %>% anti_join(stop.words)
  
  # pairwise_count() counts #token-pairs co-occuring in docs
  word_pairs = tokens %>% pairwise_count(word, docID, sort = TRUE, upper = FALSE)# %>% # head()
  
  word_counts = tokens %>% count( word,sort = T) %>% dplyr::rename( wordfr = n)
  
  word_pairs = word_pairs %>% left_join(word_counts, by = c("item1" = "word"))
  
  row_thresh = min(nrow(word_pairs), max_edges)
  
  # now plot
  set.seed(1234)
  # windows()
  plot_d <- word_pairs %>%
    filter(n >= 3) %>%
    top_n(row_thresh) %>%   igraph::graph_from_data_frame() 
  
  dfwordcloud = data_frame(vertices = names(V(plot_d))) %>% left_join(word_counts, by = c("vertices"= "word"))
  
  plot_obj = plot_d %>%   # graph object built!
    
    ggraph(layout = "fr") +
    geom_edge_link(aes(edge_alpha = n, edge_width = n), edge_colour = "cyan4")  +
    # geom_node_point(size = 5) +
    geom_node_point(size = log(dfwordcloud$wordfr)) +
    geom_node_text(aes(label = name), repel = TRUE, 
                   point.padding = unit(0.2, "lines"),
                   size = 1 + log(dfwordcloud$wordfr)) +
    theme_void()
  
  return(plot_obj)    # must return func output
  
}  # func ends

# quick example for above using amazon nokia corpus
# nokia = readLines('https://github.com/sudhir-voleti/sample-data-sets/raw/master/text%20analysis%20data/amazon%20nokia%20lumia%20reviews.txt')
# system.time({ b0=build_cog_ggraph(nokia) });  b0    # 0.36 secs

# +++

## === func 2 build cog_ggraph from dtm directly ===
dtm.2.ggraph <- function(dtm, 
                         max_tokens = 30,
                         max_edges = 150, 
                         drop.stop_words=TRUE,
                         new.stopwords=NULL)
{    # func opens
  require(tidyverse)
  require(tidytext)
  
  # remove stopwords from dtm
  stop.words1 = c(tidytext::stop_words$word, new.stopwords);    # length(stop.words1) 
  logi.vec1 = (colnames(dtm) %in% stop.words1);   #  logi.vec1 %>% head();    sum(logi.vec1)
  if (sum(logi.vec1) >0) {dtm = dtm[, !(logi.vec1)]}  # drop DTM colmns which are stopwords
  
  # choose a sample of say top max_tokens words that remain and continue
  dtm.col.sum = apply(dtm, 2, sum)
  a0 = sort(dtm.col.sum, decreasing=TRUE, index.return=TRUE)
  dtm = dtm[,(a0$ix[1:max_tokens])];  #  dim(nokia_dtm2)
  dtm = as.matrix(dtm)
  tt.mat = t(dtm) %*% dtm;  #  dim(tt.mat)
  
  # build word-pair type df now based on tt.mat lower triangular
  diag(tt.mat) = 0
  n = ncol(tt.mat); n1 = n*(n-1)/2
  word_pairs = data.frame(item1=character(n1), item2=character(n1), n=numeric(n1), stringsAsFactors=FALSE)
  
  i0 = 0
  for (i1 in 1:(n-1)){
    for (i2 in (i1+1):n){
      
      i0 = i0+1
      word_pairs$item1[i0] = colnames(tt.mat)[i1]
      word_pairs$item2[i0] = rownames(tt.mat)[i2]
      word_pairs$n[i0] = tt.mat[i2, i1]
      
    }}
  
  # Insert wordfreq as new colmn to word_pairs
  dtm.col.sum = apply(dtm, 2, sum) 
  word_counts = data.frame(word=colnames(dtm), wordfr = dtm.col.sum, stringsAsFactors=FALSE)
  word_pairs = word_pairs %>% left_join(word_counts, by = c("item1" = "word"))
  row_thresh = min(nrow(word_pairs), max_edges)
  
  # now plot
  set.seed(1234)
  # windows()
  plot_d <- word_pairs %>% 
    filter(n >= 3) %>%
    top_n(row_thresh) %>%   igraph::graph_from_data_frame() # graph object built!
  
  dfwordcloud = data_frame(vertices = names(V(plot_d))) %>% 
    left_join(word_counts, by = c("vertices"= "word"))
  
  # build ggraph now
  plot_obj = plot_d %>%   
    ggraph(layout = "fr") +
    geom_edge_link(aes(edge_alpha = n, edge_width = n), edge_colour = "cyan4")  +
    # geom_node_point(size = 5) +
    geom_node_point(size = log(dfwordcloud$wordfr)) +
    geom_node_text(aes(label = name), repel = TRUE, 
                   point.padding = unit(0.2, "lines"),
                   size = 1 + log(dfwordcloud$wordfr)) +
    theme_void()
  
  return(plot_obj) 
  
} # dtm.2.ggraph() func ends


build_kmeans_scree <- function(mydata)  # rows are units, colms are basis variables
{ # Determine number of clusters
  set.seed(seed = 0000)   # set seed for reproducible work
  wss <- (nrow(mydata)-1)*sum(apply(mydata,2,var))  # wss is within group sum of squares
  
  for (i in 2:15) wss[i] <- sum(      # checking model fit for 2 to 15 clusters
    kmeans(mydata,  centers = i)$withinss)  # note use of kmeans() func
  
  plot(1:15, wss, type="b",  # scree.plot = 
       xlab="Number of Clusters",
       ylab="Within groups sum of squares")
  
} # func ends

display.clusters <- function(dtm, k)  # k=optimal num of clusters
{ 
  
  # K-Means Cluster Analysis
  fit <- kmeans(dtm, k) # k cluster solution
  
  for (i1 in 1:max(fit$cluster)){ 
    #	windows()
    dtm_cluster = dtm[(fit$cluster == i1),] 
    distill.cog(dtm_cluster) 	} # i1 loop ends
  
}  # func ends


# check with sample dataset
# ibm = readLines("https://raw.githubusercontent.com/sudhir-voleti/sample-data-sets/master/International%20Business%20Machines%20(IBM)%20Q3%202016%20Results%20-%20Earnings%20Call%20Transcript.txt")
# source("https://raw.githubusercontent.com/sudhir-voleti/code-chunks/master/cba%20tidytext%20funcs%20for%20git%20upload.R")
# dtm.ibm = ibm %>% 
#		text.clean(., remove_numbers=FALSE) %>% 
#		dtm_build(.) %>% 
#		streamline_dtm(., min_occur=0.01, max_occur=0.80)
#  dtm.2.ggraph(dtm.ibm, max_tokens=50)	
