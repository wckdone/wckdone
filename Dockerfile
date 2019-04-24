FROM ruby:2.6.2

RUN apt-get update -y
RUN apt-get install -yff apt-utils
RUN apt-get install -yff sudo

RUN useradd -ms /bin/bash wckdone
RUN usermod -G sudo wckdone

RUN sed -i 's/^\%sudo.*$/%sudo   ALL=(ALL:ALL) NOPASSWD:ALL/' /etc/sudoers

RUN apt-get install -yff build-essential git

RUN apt-get install -yff libssl-dev libreadline-dev zlib1g-dev imagemagick

RUN gem install rerun
