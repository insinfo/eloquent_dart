<?php

class Grammar
{
  
    protected $tablePrefix = '';

   
    public function wrapArray(array $values)
    {
        return array_map([$this, 'wrap'], $values);
    }

    public function wrap($value, $prefixAlias = false)
    {
        if ($this->isExpression($value)) {
            return $this->getValue($value);
        }

        // If the value being wrapped has a column alias we will need to separate out
        // the pieces so we can wrap each of the segments of the expression on it
        // own, and then joins them both back together with the "as" connector.
        if (strpos(strtolower($value), ' as ') !== false) {
            $segments = explode(' ', $value);

            if ($prefixAlias) {
                $segments[2] = $this->tablePrefix.$segments[2];
            }

            return $this->wrap($segments[0]).' as '.$this->wrapValue($segments[2]);
        }

        $wrapped = [];

        $segments = explode('.', $value);

        // If the value is not an aliased table expression, we'll just wrap it like
        // normal, so if there is more than one segment, we will wrap the first
        // segments as if it was a table and the rest as just regular values.
        foreach ($segments as $key => $segment) {
            if ($key == 0 && count($segments) > 1) {
                $wrapped[] = $this->wrapTable($segment);
            } else {
                $wrapped[] = $this->wrapValue($segment);
            }
        }

        return implode('.', $wrapped);
    }
}

var_dump( (new Grammar())->wrapArray(['isaque','tiago']));