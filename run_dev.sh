#!/bin/sh

export DATABASE_URL="mysql2://root:password@mysql"
export REDIS_URL="redis"
export APP_ENV="development"

sudo bundle install

sudo gem install rerun

ruby db/create_database.rb && sequel -m db/migrations $DATABASE_URL/wckdone && ruby test/create_users.rb

sequel -m db/migrations $DATABASE_URL/wckdone

rerun 'rackup --host 0.0.0.0 -p 4567'
