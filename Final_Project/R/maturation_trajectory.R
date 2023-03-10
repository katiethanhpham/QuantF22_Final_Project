
source('R/lib.R')

set.seed(42)
options(mc.cores = 6)


# load digital expression matrix and meta data
cm <- readRDS('data/dropseq_digitial_expression.Rds')
md <- readRDS('data/dropseq_meta_data.Rds')

# set basename for result files
result.bn <- 'all_samples'

# get cell-cycle score
cc <- get.cc.score(cm, seed=42)
md$cc <- cc$score
md$cc.phase <- cc$phase

# normalize data 
genes <- rownames(cm)[apply(cm > 0, 1, mean) >= 0.005 & apply(cm > 0, 1, sum) >= 3]
cat('Normalizing', length(genes), 'genes that are present in at least 0.5% of the cells AND in at least 3 cells\n')

md$mols.per.gene <- md$mols / md$genes
expr <- norm.nb.reg(cm[genes, ], md[, c('reads', 'mols.per.gene', 'cc')], pr.th = 30)
# save the normalized expression data (this could be a rather large file)
saveRDS(expr, file = sprintf('results/%s_normalized_expression.Rds', result.bn))

# keep only protein coding genes
pcg <- read.table('annotation/Mus_musculus.GRCm38.84.protein_coding_genes.txt', stringsAsFactors=FALSE)$V1
expr <- expr[rownames(expr) %in% pcg, ]
cm <- cm[rownames(cm) %in% pcg, ]

# cluster cells and remove contaminating populations
cat('Doing initial clustering\n')
cl <- cluster.the.data.simple(cm, expr, 9, seed=42)
md$init.cluster <- cl$clustering
# detection rate per cluster for some marker genes
goi <- c('Igfbp7', 'Col4a1', 'Neurod2', 'Neurod6')
det.rates <- apply(cm[goi, ] > 0, 1, function(x) aggregate(x, by=list(cl$clustering), FUN=mean)$x)
contam.clusters <- sort(unique(cl$clustering))[apply(det.rates > 1/3, 1, any)]
use.cells <- !(cl$clustering %in% contam.clusters)
cat('Of the', ncol(cm), 'cells', sum(!use.cells), 'are determined to be part of a contaminating cell population.\n')
cm <- cm[, use.cells]
expr <- expr[, use.cells]
md <- md[use.cells, ]


# fit maturation trajectory
mat.traj <- maturation.trajectory(cm, md, expr)
md <- mat.traj$md
pc.line <- mat.traj$pc.line
mt.th <- mat.traj$mt.th

# save the meta data including the maturation trajectory results
saveRDS(md, file = sprintf('results/%s_maturation_trajectory_meta_data.Rds', result.bn))


# visualize result
pdf(sprintf('results/%s_maturation_trajectory.pdf', result.bn), width = 7, height = 5)

g <- ggplot(md, aes(DMC1, DMC2)) + geom_point(aes(color=maturation.score.smooth), size=1, shape=16) + 
  scale_color_gradientn(colours=my.cols.RYG, name='Maturation score') +
  stat_density2d(n=111, na.rm=TRUE, color='black', size=0.33, alpha=0.5) +
  geom_line(data=pc.line, color='deeppink', size=0.77) +
  theme_grey(base_size=12) + labs(x='DMC1', y='DMC2')
plot(g)

g <- ggplot(md, aes(DMC1, DMC2)) + geom_point(aes(color=rank(maturation.score.smooth)), size=1, shape=16) + 
  scale_color_gradientn(colours=my.cols.RYG, name='Maturation score rank') +
  stat_density2d(n=111, na.rm=TRUE, color='black', size=0.33, alpha=0.5) +
  geom_line(data=pc.line, color='deeppink', size=0.77) +
  theme_grey(base_size=12) + labs(x='DMC1', y='DMC2')
plot(g)

g <- ggplot(md, aes(maturation.score.smooth, cc.phase.fit)) + geom_point(aes(color=postmitotic), size=2) +
  geom_hline(yintercept =  mean(md$in.cc.phase)/2) + geom_vline(xintercept = mt.th) +
  theme_grey(base_size=12) + labs(x='Maturation score', y='Fraction of cells in G2/M or S phase')
plot(g)

g <- ggplot(md, aes(DMC1, DMC2)) + geom_point(aes(color=postmitotic), size=1, shape=16) +
  theme_grey(base_size=12) + labs(x='DMC1', y='DMC2')
plot(g)
dev.off()


# create smooth expression (as function of maturation score) for visualization later on
x.pred <- seq(min(md$maturation.score.smooth), max(md$maturation.score.smooth), length.out=100)
c.cge <- which(md$eminence == 'CGE')
c.lge <- which(md$eminence == 'LGE')
c.mge <- which(md$eminence == 'MGE')
expr.cge.fit <- smooth.expr(expr[, c.cge], md$maturation.score.smooth[c.cge], x.pred)
expr.lge.fit <- smooth.expr(expr[, c.lge], md$maturation.score.smooth[c.lge], x.pred)
expr.mge.fit <- smooth.expr(expr[, c.mge], md$maturation.score.smooth[c.mge], x.pred)
expr.all.fit <- smooth.expr(expr, md$maturation.score.smooth, x.pred)
fit.lst <- list(all=expr.all.fit, CGE=expr.cge.fit, LGE=expr.lge.fit, MGE=expr.mge.fit)
# save the smooth expression data
saveRDS(fit.lst, file = sprintf('results/%s_smooth_expression.Rds', result.bn))
