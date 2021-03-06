library(rpart)
library(rpart.plot)
library(gains)

# from https://www.kaggle.com/c/titanic/data
# see link for data dictionary
titanic.data <- read_csv("./data/titanic/train.csv")
titanic.data
dim(titanic.data)

# confusionMatrix() works best if the target is a factor
# rather than a numeric or logical variable
titanic.data$Survived <- as.factor(titanic.data$Survived)

# partition into training and test sets
set.seed(12345)
train.proportion <- 0.75
val.proportion <- 0.25

train.index <- sample(1:nrow(titanic.data), nrow(titanic.data)*train.proportion)
train.data <- titanic.data[train.index,]
validation.data <- titanic.data[-train.index,]

# data exploration
View(train.data)

# verify which variables are ready to use directly
table(train.data$Survived)
table(train.data$Pclass)
length(unique(train.data$Name))
table(train.data$Sex)
summary(train.data$Age)
table(train.data$SibSp)
table(train.data$Parch)
length(unique(train.data$Ticket))
summary(train.data$Fare)
length(unique(train.data$Cabin))
length(unique(train.data$Embarked))

# 'Age' is probably useful but has many missing values
# come back to this later

# train a classification tree to predict passenger survival
# use only "tidy" variables
# aka those which are either numeric or have a small number of classes
surv.tree.1 <- rpart(Survived ~ Pclass + Sex + SibSp + Parch + Fare + Embarked,
                     data=train.data,
                     method="class")

prp(surv.tree.1, type=1, extra=1, under=TRUE, split.font=2, varlen=-10)

# try some different parameters for minsplit, minbucket, maxdepth, 
# cp (complexity parameter; default = 0.01)
# ?rpart.control explains meaning of these parameters
surv.tree.2 <- rpart(Survived ~ Pclass + Sex + SibSp + Parch + Fare + Embarked,
                     data=train.data,
                     method="class"
                     ,maxdepth=3
                     )
prp(surv.tree.2, type=1, extra=1, under=TRUE, split.font=2, varlen=-10)


surv.tree.3 <- rpart(Survived ~ Pclass + Sex + SibSp + Parch + Fare + Embarked,
                     data=train.data,
                     method="class"
                     ,minsplit=40
                     )
prp(surv.tree.3, type=1, extra=1, under=TRUE, split.font=2, varlen=-10)


surv.tree.4 <- rpart(Survived ~ Pclass + Sex + SibSp + Parch + Fare + Embarked,
                     data=train.data,
                     method="class",
                     cp=0.002
)
prp(surv.tree.4, type=1, extra=1, under=TRUE, split.font=2, varlen=-10)

# measure performance against a validation set
validation.data$preds.tree.1 <- predict(surv.tree.1,
                                        newdata=validation.data,
                                        type="class")
summary(validation.data$preds.tree.1)

confusionMatrix(validation.data$preds.tree.1,
                validation.data$Survived)

# get probabilities instead
probs.tree.1 <- predict(surv.tree.1,
                        newdata=validation.data,
                        type="prob")
head(probs.tree.1)
validation.data$survival.probs.1 <- probs.tree.1[,2]

# aside: where do these probabilities actually come from?

# plot a lift chart with the probabilities
gain <- gains(as.numeric(validation.data$Survived), 
              validation.data$survival.probs.1,
              groups=10)
gain

# set up lift chart variables
total.survived <- sum(as.numeric(validation.data$Survived))
yvals <- c(0,gain$cume.pct.of.total*total.survived)
xvals <- c(0,gain$cume.obs)

# plot the actual lift chart
ggplot() + 
  geom_line(mapping = aes(x=xvals, y=yvals)) +
  xlab("Predicted Survivors") + ylab("Actual Survivors") + 
  ggtitle("Tree #1 Validation") + 
  theme(plot.title = element_text(hjust = 0.5)) + 
  geom_abline(intercept = c(0,0), 
              slope=total.survived/nrow(validation.data),
              linetype="dashed")

# aside: not too many actual points on the curve - why is this?
table(validation.data$survival.probs.1)


### Parameter Tuning ###

# plot accuracy vs training, accuracy vs holdout against CP
cps <- c(0.0001, 0.0002, 0.0005, 0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1)
balanced.accuracy.train <- c()
balanced.accuracy.val <- c()

# set minsplit, minbucket, maxdepth to be extremely loose so that only 
# cp (complexity parameter) determines the tree shape
for (cp in cps) {
  print(cp)
  surv.tree.cp <- rpart(Survived ~ Pclass + Sex + SibSp + Parch + Fare + Embarked + Age,
                       data=train.data,
                       method="class",
                       cp=cp,
                       minsplit=2,
                       minbucket=1,
                       maxdepth=30,
                       xval=0
  )
  
  # get predictions for each value in the training and validation sets
  train.preds <- predict(surv.tree.cp, newdata=train.data, type="class")
  val.preds <- predict(surv.tree.cp, newdata=validation.data, type="class")
  
  # confusion matrix for train and test sets
  cm.train <- confusionMatrix(train.preds, train.data$Survived)
  cm.val <- confusionMatrix(val.preds, validation.data$Survived)
  
  # pull out balanced accuracy from each confusion matrix and add it to the array
  balanced.accuracy.train <- c(balanced.accuracy.train,
                               cm.train$byClass['Balanced Accuracy'])
  balanced.accuracy.val <- c(balanced.accuracy.val,
                             cm.val$byClass['Balanced Accuracy'])
}

# set up a dataframe to plot both series with a legend
train.accuracy <- data.frame("cp"=cps,
                             "dataset"="Training",
                             "accuracy"=balanced.accuracy.train)
val.accuracy <- data.frame("cp"=cps,
                             "dataset"="Validation",
                             "accuracy"=balanced.accuracy.val)
full.accuracy <- rbind(train.accuracy, val.accuracy)

# plot the performance vs. complexity parameter
ggplot(data=full.accuracy) + 
  geom_line(mapping = aes(x=cp, y=accuracy, col=dataset)) + 
  ylab("Balanced Accuracy") + 
  scale_x_log10(labels = scales::label_number(accuracy=0.001))


# NOTES:
# apparently rpart has no problem with variables that have some NA values e.g. Embarked, Age

