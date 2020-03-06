FROM ruby:2.6-slim
MAINTAINER Ben Ford <ben.ford@puppet.com>
WORKDIR /var/cache/mvp
RUN gem install puppet-community-mvp --no-document
CMD ["mvp", "--config", "/var/run/mvp/config.yaml", "mirror", "all"]

# FROM gliderlabs/alpine
# RUN apk update && apk add --no-cache ruby ruby-dev build-base                     \
#         && gem install etc puppet-community-mvp puppet-itemize bigdecimal puppet --no-ri --no-rdoc  \
#         && apk del --purge binutils isl libgomp libatomic libgcc mpfr3 mpc1 libstdc++ gcc musl-dev libc-dev g++ make fortify-headers build-base libgmpxx gmp-dev ruby-dev \
#         && rm -rf /var/cache/apk/*                             \
#         && rm -rf `gem environment gemdir`/cache               \
#         && rm -rf /tmp/*
